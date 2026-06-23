require 'rails_helper'

RSpec.describe IngestionBatch, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:ingestion_batch)).to be_valid
    end

    it 'requires a name' do
      expect(build(:ingestion_batch, name: nil)).not_to be_valid
    end

    it 'requires a source_type' do
      expect(build(:ingestion_batch, source_type: nil)).not_to be_valid
    end
  end

  describe 'status predicates' do
    it 'exposes? predicate methods for each status' do
      batch = create(:ingestion_batch, status: :initializing)
      expect(batch.initializing?).to be(true)
      expect(batch.committed?).to be(false)
    end
  end

  describe '#progress_pct' do
    it 'returns 0 when total_count is zero' do
      batch = build(:ingestion_batch, total_count: 0, processed_count: 0)
      expect(batch.progress_pct).to eq(0)
    end

    it 'calculates percentage correctly' do
      batch = build(:ingestion_batch, total_count: 10, processed_count: 4)
      expect(batch.progress_pct).to eq(40.0)
    end
  end
end
