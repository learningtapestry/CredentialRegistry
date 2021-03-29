require 'indexed_envelope_resource'
require 'indexed_envelope_resource_reference'
require 'json_context'
require 'postgres_ext'

# Executes a CTDL query over indexed envelope resources
class CtdlQuery
  IMPOSSIBLE_CONDITION = Arel::Nodes::InfixOperation.new('=', 0, 1)

  SearchValue = Struct.new(:items, :operator, :match_type)

  TYPES = {
    'xsd:boolean' => :boolean,
    'xsd:date' => :date,
    'xsd:decimal' => :decimal,
    'xsd:dateTime' => :datetime,
    'xsd:float' => :float,
    'xsd:integer' => :integer
  }.freeze

  attr_reader :condition, :name, :projections, :query, :ref, :skip,
              :string_array_query, :subqueries, :table, :take

  delegate :columns_hash, to: IndexedEnvelopeResource
  delegate :context, to: JsonContext

  def initialize(query, name: nil, project: [], ref: nil, skip: nil, take: nil)
    @name = name
    @projections = Array(project)
    @query = query
    @ref = ref
    @skip = skip
    @string_array_query = ref && Array(query).first.is_a?(String)
    @subqueries = []
    @table = IndexedEnvelopeResource.arel_table
    @take = take

    @condition = build(query) unless string_array_query
  end

  def execute
    IndexedEnvelopeResource.connection.execute(to_sql)
  end

  def to_sql
    @sql ||= begin
      if subqueries.any?
        cte = <<~SQL.strip
          WITH #{subqueries.map { |q| "#{q.name} AS (#{q.to_sql})" }.join(', ')}
        SQL
      end

      relation = table.where(condition) if condition
      relation = relation.skip(skip) if skip
      relation = relation.take(take) if take

      relation =
        if ref.present?
          ref_table = IndexedEnvelopeResourceReference.arel_table

          relation =
            if string_array_query
              ref_table.where(ref_table[:subresource_uri].in(Array(query)))
            else
              (relation || table)
                .join(ref_table)
                .on(table[:@id].eq(ref_table[:subresource_uri]))
            end

          relation
            .where(ref_table[:path].eq(ref))
            .project(ref_table[:resource_id])
        else
          relation.project(*projections)
        end

      [cte, relation.to_sql].join(' ').strip
    end
  end

  private

  def build(node)
    combine_conditions(build_node(node), find_operator(node))
  end

  def build_array_condition(key, value)
    return table[key].not_eq([]) if value.items == ['search:anyValue']

    datatype = TYPES.fetch(context.dig(key, '@type'), :string)

    if value.items.size == 2 && datatype != :string
      range = Range.new(*value.items)
      return Arel::Nodes::ArrayAccess.new(table[key], 1).between(range)
    end

    operator = value.operator == :and ? :contains : :overlap
    table[key].send(operator, value.items)
  end

  def build_condition(key, value)
    context_entry = context.fetch(key, {})
    column = columns_hash[key]

    if context_entry['@type'] == '@id'
      return build_subquery_condition(key, value)
    end

    raise "Unsupported property: #{key}" unless column

    search_value = build_search_value(value)

    if %w[@id ceterms:ctid].include?(key)
      build_id_condition(key, search_value.items)
    elsif context_entry['@container'] == '@language'
      build_fts_conditions(key, search_value)
    elsif context_entry['@type'] == 'xsd:string'
      build_fts_condition('simple', key, search_value.items)
    elsif column.array
      build_array_condition(key, search_value)
    else
      build_scalar_condition(key, search_value)
    end
  end

  def build_from_array(node)
    node.map { |item| build(item) }
  end

  def build_from_hash(node)
    node = node.fetch('search:value', node)
    return build_from_array(node) if node.is_a?(Array)

    if (term_group = node['search:termGroup'])
      conditions = build_from_hash(node.except('search:termGroup'))
      return conditions << build(term_group)
    end

    node.map do |key, value|
      next if key == 'search:operator'

      build_condition(key, value)
    end.compact
  end

  def build_fts_condition(config, key, term)
    return table[key].not_eq(nil) if term == 'search:anyValue'

    if term.is_a?(Array)
      conditions = term.map { |t| build_fts_condition(config, key, t) }
      return combine_conditions(conditions, :or)
    end

    term = term.fetch('search:value') if term.is_a?(Hash)
    quoted_config = Arel::Nodes.build_quoted(config)
    query = term.gsub(/[\.\/]/, ' ')

    translated_column = Arel::Nodes::NamedFunction.new(
      'translate',
      [
        table[key],
        Arel::Nodes.build_quoted('/.'),
        Arel::Nodes.build_quoted(' ')
      ]
    )

    column_vector = Arel::Nodes::NamedFunction.new(
      'to_tsvector',
      [quoted_config, translated_column]
    )

    query_vector = Arel::Nodes::NamedFunction.new(
      'plainto_tsquery',
      [quoted_config, Arel::Nodes.build_quoted(query)]
    )

    Arel::Nodes::InfixOperation.new('@@', column_vector, query_vector)
  end

  def build_fts_conditions(key, value)
    conditions = value.items.map do |item|
      if item.is_a?(Hash)
        conditions = item.map do |locale, term|
          name = "#{key}_#{locale.tr('-', '_').downcase}"
          column = columns_hash[name]
          next IMPOSSIBLE_CONDITION unless column

          config =
            if locale.starts_with?('es')
              'spanish'
            elsif locale.starts_with?('fr')
              'french'
            else
              'simple'
            end

          build_fts_condition(config, name, term)
        end
      elsif item.is_a?(SearchValue)
        build_fts_condition('simple', key, item.items)
      elsif item.is_a?(String)
        build_fts_condition('simple', key, item)
      else
        raise "FTS condition should be either an object or a string, `#{item}` is neither"
      end
    end.flatten

    combine_conditions(conditions, value.operator)
  end

  def build_id_condition(key, values)
    conditions = values.map do |value|
      if full_id_value?(key, value)
        table[key].eq(value)
      else
        table[key].matches("%#{value}%")
      end
    end

    combine_conditions(conditions, :or)
  end

  def build_node(node)
    case node
    when Array then build_from_array(node)
    when Hash then build_from_hash(node)
    else raise "Either an array or object is expected, `#{node}` is neither"
    end
  end

  def build_scalar_condition(key, value)
    if %w[@id ceterms:ctid].include?(key)
      build_id_condition(key, value.items)
    else
      table[key].in(value.items)
    end
  end

  def build_search_value(value)
    case value
    when Array
      items =
        if value.first.is_a?(String)
          value
        else
          value.map { |item| build_search_value(item) }
        end

      SearchValue.new(items, :or)
    when Hash
      SearchValue.new(
        value.fetch(
          'search:value',
          [value.except('search:matchType', 'search:operator')]
        ),
        find_operator(value),
        value['search:matchType']
      )
    when String
      SearchValue.new([value])
    else
      value
    end
  end

  def build_subquery_condition(key, value)
    subquery_name = generate_subquery_name(key)
    subqueries << CtdlQuery.new(value, name: subquery_name, ref: key)
    table[:id].in(Arel.sql("(SELECT resource_id FROM #{subquery_name})"))
  end

  def combine_conditions(conditions, operator)
    conditions.inject { |result, condition| result.send(operator, condition) }
  end

  def find_operator(node)
    return :or if node.is_a?(Array)

    node['search:operator'] == 'search:orTerms' ? :or : :and
  end

  def full_id_value?(key, value)
    case key
    when '@id' then valid_bnode?(value) || valid_uri?(value)
    when 'ceterms:ctid' then valid_ceterms_ctid?(value)
    else false
    end
  end

  def generate_subquery_name(key)
    value = [name, key.tr(':', '_')].compact.join('_')

    indices = subqueries.map do |subquery|
      match_data = /#{value}_?(?<index>\d+)?/.match(subquery.name)
      match_data['index'].to_i if match_data
    end

    last_index = indices.compact.sort.last
    return value unless last_index

    "#{value}_#{last_index + 1}"
  end

  def valid_bnode?(value)
    !!UUID.validate(value[2..value.size - 1])
  end

  def valid_ceterms_ctid?(value)
    !!UUID.validate(value[3..value.size - 1])
  end

  def valid_uri?(value)
    URI.parse(value).is_a?(URI::HTTP)
  rescue URI::InvalidURIError
    false
  end
end
