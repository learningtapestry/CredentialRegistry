require 'envelope'
require 'envelope_resource'

RSpec.describe EnvelopeResource, type: :model do
  describe 'select_scope' do
    let!(:envelopes) do
      Array.new(3) do
        create(:envelope, :from_cer, :with_graph_competency_framework, resource: make_resource,
                                                                       skip_validation: true)
      end
    end

    before { envelopes.first.mark_as_deleted! }

    it 'uses default_scope if no param is given' do
      expect(described_class.select_scope.count).to eq 10
    end

    it 'gets all entries when include_deleted=true' do
      expect(described_class.select_scope('true').count).to eq 15
    end

    it 'gets only deleted etries when include_deleted=only' do
      expect(described_class.select_scope('only').count).to eq 5
    end
  end

  describe '.in_community' do
    let!(:envelope) do
      create(:envelope, :from_cer, :with_graph_competency_framework, skip_validation: true)
    end
    let!(:name)     { envelope.envelope_community.name }
    let!(:ec)       { create(:envelope_community, name: 'test').name }

    it 'find envelopes with community' do
      expect(described_class.in_community(name).count).to eq(5)
    end

    it 'find envelopes with `nil` community' do
      expect(described_class.in_community(nil).count).to eq(5)
    end

    it 'doesn\'t find envelopes from other communities' do
      expect(described_class.in_community(ec).count).to eq(0)
    end
  end

  def make_resource
    jwt_encode(attributes_for(:cer_graph_competency_framework, ctid: Envelope.generate_ctid))
  end
end
