class CreateIndexedEnvelopeResourceReferences < ActiveRecord::Migration[5.2]
  def change
    create_table :indexed_envelope_resource_references do |t|
      t.string :path, null: false

      t.references :resource,
                   foreign_key: {
                     on_delete: :cascade,
                     to_table: :indexed_envelope_resources
                   },
                   index: false,
                   null: false

      t.string :subresource_uri, null: false

      t.index %i[path resource_id subresource_uri],
              name: 'index_indexed_envelope_resource_references',
              unique: true
    end
  end
end
