require 'rails_helper'

RSpec.describe AssetDownload, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:asset_download)).to be_valid
    end

    it 'requires a name' do
      expect(build(:asset_download, name: nil)).not_to be_valid
    end
  end

  describe 'constants' do
    it 'retains generated ZIPs for 7 days' do
      expect(described_class::RETENTION_PERIOD).to eq(7.days)
    end
  end

  describe 'scopes' do
    it '.not_expired excludes records past their expiry' do
      active  = create(:asset_download, :completed)
      expired = create(:asset_download, :expired)

      expect(described_class.not_expired).to include(active)
      expect(described_class.not_expired).not_to include(expired)
      expect(described_class.expired).to include(expired)
    end

    it '.active_for scopes to a user\'s pending/processing downloads only' do
      user = create(:user)
      pending_download    = create(:asset_download, user: user, status: :pending)
      processing_download = create(:asset_download, :processing, user: user)
      completed_download  = create(:asset_download, :completed, user: user)
      other_user_download  = create(:asset_download, status: :pending)

      scoped = described_class.active_for(user)
      expect(scoped).to include(pending_download, processing_download)
      expect(scoped).not_to include(completed_download, other_user_download)
    end
  end

  describe '#expired?' do
    it 'reflects the expiry timestamp' do
      expect(build(:asset_download, :expired).expired?).to be(true)
      expect(build(:asset_download, :completed).expired?).to be(false)
    end
  end

  describe '#progress_percent' do
    it 'is 0 when no items have been processed yet' do
      expect(build(:asset_download, total_items: 10, processed_items: 0).progress_percent).to eq(0)
    end

    it 'is 100 once completed, regardless of the raw ratio' do
      expect(build(:asset_download, :completed, total_items: 10, processed_items: 10).progress_percent).to eq(100)
    end

    it 'caps below 100 while still processing, even at a 100% raw ratio' do
      dl = build(:asset_download, status: :processing, total_items: 10, processed_items: 10)
      expect(dl.progress_percent).to eq(99)
    end

    it 'is 0 when total_items is zero (avoids a divide-by-zero)' do
      expect(build(:asset_download, total_items: 0, processed_items: 0).progress_percent).to eq(0)
    end

    it 'computes the whole-percent ratio while processing' do
      dl = build(:asset_download, status: :processing, total_items: 4, processed_items: 1)
      expect(dl.progress_percent).to eq(25)
    end
  end
end
