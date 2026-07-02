# frozen_string_literal: true

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
    it 'exposes ? predicate methods for each status' do
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

  describe 'named scopes' do
    let!(:initializing_batch) { create(:ingestion_batch, status: :initializing) }
    let!(:extracting_batch)   { create(:ingestion_batch, status: :extracting) }
    let!(:transforming_batch) { create(:ingestion_batch, status: :transforming) }
    let!(:review_batch)       { create(:ingestion_batch, status: :review_needed) }
    let!(:committed_batch)    { create(:ingestion_batch, status: :committed) }
    let!(:failed_batch)       { create(:ingestion_batch, status: :failed) }

    describe '.in_progress' do
      it 'includes initializing, extracting, transforming and review_needed batches' do
        result = described_class.in_progress
        expect(result).to include(initializing_batch, extracting_batch, transforming_batch, review_batch)
        expect(result).not_to include(committed_batch, failed_batch)
      end
    end

    describe '.committed_batches' do
      it 'returns only committed batches' do
        expect(described_class.committed_batches).to contain_exactly(committed_batch)
      end
    end

    describe '.failed_batches' do
      it 'returns only failed batches' do
        expect(described_class.failed_batches).to contain_exactly(failed_batch)
      end
    end

    describe '.search_by_name' do
      let!(:named_batch) { create(:ingestion_batch, name: 'Cloudinary Legacy Import') }

      it 'finds batches matching the query (case-insensitive)' do
        expect(described_class.search_by_name('cloudinary')).to include(named_batch)
      end

      it 'does not find batches that do not match' do
        expect(described_class.search_by_name('bynder')).not_to include(named_batch)
      end
    end
  end

  describe '.aggregate_stats' do
    before do
      create(:ingestion_batch, status: :committed,    total_count: 100, committed_count: 90,  duplicate_count: 10, error_count: 0)
      create(:ingestion_batch, status: :extracting,   total_count: 50,  committed_count: 0,   duplicate_count: 5,  error_count: 2)
      create(:ingestion_batch, status: :failed,       total_count: 20,  committed_count: 0,   duplicate_count: 0,  error_count: 5)
    end

    subject(:stats) { described_class.aggregate_stats }

    it 'counts total batches correctly' do
      expect(stats[:total_batches]).to eq(3)
    end

    it 'counts active (in-progress) batches' do
      expect(stats[:active_batches]).to eq(1)
    end

    it 'counts completed batches' do
      expect(stats[:completed_batches]).to eq(1)
    end

    it 'counts failed batches' do
      expect(stats[:failed_batches]).to eq(1)
    end

    it 'sums total_assets_staged' do
      expect(stats[:total_assets_staged]).to eq(170)
    end

    it 'sums total_assets_committed' do
      expect(stats[:total_assets_committed]).to eq(90)
    end

    it 'sums total_duplicates_blocked' do
      expect(stats[:total_duplicates_blocked]).to eq(15)
    end

    it 'returns estimated_storage_saved_gb as a float' do
      expect(stats[:estimated_storage_saved_gb]).to be_a(Float)
    end

    it 'returns estimated_cost_savings_usd as a float' do
      expect(stats[:estimated_cost_savings_usd]).to be_a(Float)
    end
  end

  describe '#summary' do
    it 'includes all expected keys' do
      batch = create(:ingestion_batch)
      keys  = batch.summary.keys
      expect(keys).to include(:id, :name, :source_type, :status, :progress_pct,
                               :total_count, :processed_count, :committed_count,
                               :duplicate_count, :error_count, :source_label,
                               :destination_folder_id, :destination_folder_name)
    end

    it 'surfaces the destination folder when set' do
      folder = create(:folder, name: 'Campaign Assets')
      batch  = create(:ingestion_batch, destination_folder: folder)

      expect(batch.summary[:destination_folder_id]).to eq(folder.id)
      expect(batch.summary[:destination_folder_name]).to eq('Campaign Assets')
    end
  end

  describe 'associations' do
    it 'optionally belongs to a destination folder' do
      expect(build(:ingestion_batch, destination_folder: nil)).to be_valid
      folder = create(:folder)
      expect(create(:ingestion_batch, destination_folder: folder).destination_folder).to eq(folder)
    end
  end
end
