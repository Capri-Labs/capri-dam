require 'rails_helper'

RSpec.describe IngestionItem, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:ingestion_item)).to be_valid
    end

    it 'requires an original_filename' do
      expect(build(:ingestion_item, original_filename: nil)).not_to be_valid
    end
  end

  describe 'status predicates' do
    it 'exposes ? predicate for each status' do
      item = create(:ingestion_item, status: :pending)
      expect(item.pending?).to be(true)
      expect(item.committed?).to be(false)
    end
  end

  describe 'associations' do
    it 'belongs to an ingestion_batch' do
      item = create(:ingestion_item)
      expect(item.ingestion_batch).to be_present
    end
  end
end
