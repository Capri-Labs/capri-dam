require 'rails_helper'

RSpec.describe ReportSnapshot, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:report_snapshot)).to be_valid
    end

    it 'requires format to be csv, pdf, or xlsx' do
      expect(build(:report_snapshot, format: 'txt')).not_to be_valid
      expect(build(:report_snapshot, format: 'csv')).to be_valid
      expect(build(:report_snapshot, format: 'pdf')).to be_valid
      expect(build(:report_snapshot, format: 'xlsx')).to be_valid
    end
  end

  describe 'status enum' do
    it 'can be set to pending' do
      snap = build(:report_snapshot, status: :pending)
      expect(snap.status).to eq('pending')
    end

    it 'factory defaults to processing (status: 1)' do
      snap = build(:report_snapshot)
      expect(snap.status).to eq('processing')
    end
  end

  describe 'associations' do
    it 'belongs to a report_definition' do
      snap = create(:report_snapshot)
      expect(snap.report_definition).to be_present
    end
  end
end
