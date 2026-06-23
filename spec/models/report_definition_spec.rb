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
end
