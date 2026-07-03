require 'rails_helper'

RSpec.describe ReportDefinition, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:report_definition)).to be_valid
    end

    it 'requires a name' do
      expect(build(:report_definition, name: nil)).not_to be_valid
    end

    it 'requires a report_type' do
      expect(build(:report_definition, report_type: nil)).not_to be_valid
    end
  end

  describe 'associations' do
    it 'has many report_snapshots' do
      rd = create(:report_definition)
      snap = create(:report_snapshot, report_definition: rd)
      expect(rd.report_snapshots).to include(snap)
    end
  end

  describe '#description' do
    it 'returns the configured description when present' do
      definition = build(:report_definition, query_config: { 'description' => 'Usage by folder' })

      expect(definition.description).to eq('Usage by folder')
    end

    it 'returns nil when query_config is nil or missing the description key' do
      expect(build(:report_definition, query_config: nil).description).to be_nil
      expect(build(:report_definition, query_config: { 'title' => 'No description' }).description).to be_nil
    end
  end
end
