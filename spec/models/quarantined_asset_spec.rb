require 'rails_helper'

RSpec.describe QuarantinedAsset, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:quarantined_asset)).to be_valid
    end

    it 'requires a status from the allowed list' do
      expect(build(:quarantined_asset, status: 'unknown')).not_to be_valid
    end
  end

  describe 'default status' do
    it 'defaults to pending_review on create' do
      qa = create(:quarantined_asset, status: nil)
      expect(qa.status).to eq('pending_review')
    end
  end

  describe 'associations' do
    it 'belongs to a system_connector' do
      qa = create(:quarantined_asset)
      expect(qa.system_connector).to be_present
    end
  end
end
