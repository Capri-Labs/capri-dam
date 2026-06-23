require 'rails_helper'

RSpec.describe MetadataExport, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:metadata_export)).to be_valid
    end

    it 'requires a name' do
      expect(build(:metadata_export, name: nil)).not_to be_valid
    end

    it 'only allows the documented property modes' do
      expect(build(:metadata_export, property_mode: 'bogus')).not_to be_valid
      expect(build(:metadata_export, property_mode: 'all')).to be_valid
      expect(build(:metadata_export, property_mode: 'selective')).to be_valid
    end
  end

  describe 'constants' do
    it 'caps a file at the Excel worksheet row limit' do
      expect(described_class::MAX_ROWS_PER_FILE).to eq(1_048_575)
    end

    it 'retains generated files for 30 days' do
      expect(described_class::RETENTION_PERIOD).to eq(30.days)
    end
  end

  describe '#selective?' do
    it 'is true only for selective exports' do
      expect(build(:metadata_export, :selective).selective?).to be(true)
      expect(build(:metadata_export).selective?).to be(false)
    end
  end

  describe 'scopes' do
    it '.not_expired excludes records past their expiry' do
      active  = create(:metadata_export, :completed)
      expired = create(:metadata_export, :expired)

      expect(described_class.not_expired).to include(active)
      expect(described_class.not_expired).not_to include(expired)
      expect(described_class.expired).to include(expired)
    end
  end

  describe '#expired?' do
    it 'reflects the expiry timestamp' do
      expect(build(:metadata_export, :expired).expired?).to be(true)
      expect(build(:metadata_export, :completed).expired?).to be(false)
    end
  end
end

