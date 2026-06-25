require 'rails_helper'

RSpec.describe MetadataImport, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:metadata_import)).to be_valid
    end

    it 'requires a name' do
      expect(build(:metadata_import, name: nil)).not_to be_valid
    end

    it 'rejects a batch size above the maximum' do
      expect(build(:metadata_import, batch_size: 101)).not_to be_valid
      expect(build(:metadata_import, batch_size: 100)).to be_valid
    end

    it 'requires separators and the path column' do
      expect(build(:metadata_import, field_separator: nil)).not_to be_valid
      expect(build(:metadata_import, multi_value_delimiter: nil)).not_to be_valid
      expect(build(:metadata_import, asset_path_column: nil)).not_to be_valid
    end
  end

  describe 'constants' do
    it 'defines the fixed template columns starting with asset_path' do
      expect(described_class::TEMPLATE_COLUMNS.first).to eq('asset_path')
      expect(described_class::TEMPLATE_COLUMNS).to include('copyright', 'tags')
    end

    it 'defaults batch size to 50 and caps it at 100' do
      expect(described_class::DEFAULT_BATCH_SIZE).to eq(50)
      expect(described_class::MAX_BATCH_SIZE).to eq(100)
    end
  end

  describe '#normalized_batch_size' do
    it 'clamps values into the 1..100 range' do
      expect(build(:metadata_import, batch_size: 0).normalized_batch_size).to eq(1)
      expect(build(:metadata_import, batch_size: 250).normalized_batch_size).to eq(100)
      expect(build(:metadata_import, batch_size: 25).normalized_batch_size).to eq(25)
    end
  end

  describe 'scopes' do
    it '.not_expired excludes expired imports' do
      active  = create(:metadata_import, :completed)
      expired = create(:metadata_import, :expired)

      expect(described_class.not_expired).to include(active)
      expect(described_class.not_expired).not_to include(expired)
    end
  end
end
