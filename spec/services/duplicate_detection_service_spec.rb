require "rails_helper"

RSpec.describe DuplicateDetectionService, type: :service do
  let(:user)      { create(:user) }
  let(:asset)     { create(:asset, user: user) }
  let(:checksum)  { "abc123def456abc123def456abc123def456abc123def456abc123def456abc1" }

  before do
    # Enable detection
    Setting.set("duplicate_manager_enabled", true)
    Setting.set("duplicate_manager_inbox_notifications", false)
  end

  # ---------------------------------------------------------------------------
  # When detection is disabled
  # ---------------------------------------------------------------------------
  context "when duplicate detection is disabled" do
    before { Setting.set("duplicate_manager_enabled", false) }

    it "returns a result with duplicate_group: nil" do
      result = described_class.call(asset: asset, checksum: checksum, user: user)
      expect(result.duplicate_detected?).to be false
      expect(result.enabled).to be false
    end

    it "does not create any DuplicateGroup records" do
      expect {
        described_class.call(asset: asset, checksum: checksum, user: user)
      }.not_to change(DuplicateGroup, :count)
    end
  end

  # ---------------------------------------------------------------------------
  # When no matching asset exists
  # ---------------------------------------------------------------------------
  context "when no existing asset has the same checksum" do
    it "returns a result with duplicate_group: nil" do
      result = described_class.call(asset: asset, checksum: checksum, user: user)
      expect(result.duplicate_detected?).to be false
      expect(result.enabled).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # When a matching asset exists
  # ---------------------------------------------------------------------------
  context "when an existing asset has the same checksum" do
    let!(:existing_asset)   { create(:asset, user: user) }
    let!(:existing_version) {
      create(:asset_version, asset: existing_asset,
             properties: { "checksum_sha256" => checksum })
    }

    it "creates a pending DuplicateGroup" do
      expect {
        described_class.call(asset: asset, checksum: checksum, user: user)
      }.to change(DuplicateGroup, :count).by(1)

      group = DuplicateGroup.last
      expect(group.status).to eq("pending")
      expect(group.checksum).to eq(checksum)
    end

    it "registers both assets as members" do
      described_class.call(asset: asset, checksum: checksum, user: user)
      group = DuplicateGroup.last
      expect(group.duplicate_group_assets.map(&:asset_id)).to contain_exactly(
        asset.id, existing_asset.id
      )
    end

    it "marks the older asset as is_original" do
      described_class.call(asset: asset, checksum: checksum, user: user)
      group = DuplicateGroup.last
      original_member = group.duplicate_group_assets.find_by(is_original: true)
      expect(original_member.asset_id).to eq(existing_asset.id)
    end

    it "sets total_count on the group" do
      described_class.call(asset: asset, checksum: checksum, user: user)
      expect(DuplicateGroup.last.total_count).to eq(2)
    end

    it "returns a result with the group" do
      result = described_class.call(asset: asset, checksum: checksum, user: user)
      expect(result.duplicate_detected?).to be true
      expect(result.duplicate_group).to be_a(DuplicateGroup)
    end
  end

  # ---------------------------------------------------------------------------
  # Re-detection: existing group is updated
  # ---------------------------------------------------------------------------
  context "when a pending group already exists for the checksum" do
    let!(:existing_asset)   { create(:asset, user: user) }
    let!(:existing_version) {
      create(:asset_version, asset: existing_asset,
             properties: { "checksum_sha256" => checksum })
    }
    let!(:group) { create(:duplicate_group, checksum: checksum, status: "pending") }

    before do
      create(:duplicate_group_asset, duplicate_group: group, asset: existing_asset)
    end

    it "reuses the existing group" do
      expect {
        described_class.call(asset: asset, checksum: checksum, user: user)
      }.not_to change(DuplicateGroup, :count)
    end

    it "adds the new asset to the existing group" do
      described_class.call(asset: asset, checksum: checksum, user: user)
      expect(group.reload.duplicate_group_assets.count).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # Inbox notifications
  # ---------------------------------------------------------------------------
  context "when inbox notifications are enabled" do
    let!(:existing_asset)   { create(:asset, user: user) }
    let!(:existing_version) {
      create(:asset_version, asset: existing_asset,
             properties: { "checksum_sha256" => checksum })
    }

    before { Setting.set("duplicate_manager_inbox_notifications", true) }

    it "creates a Notification for the user" do
      expect {
        described_class.call(asset: asset, checksum: checksum, user: user)
      }.to change(Notification, :count).by(1)

      notification = Notification.last
      expect(notification.user).to eq(user)
      expect(notification.action_url).to eq("/duplicates")
    end
  end

  # ---------------------------------------------------------------------------
  # Idempotency
  # ---------------------------------------------------------------------------
  context "when the same asset is detected twice" do
    let!(:existing_asset)   { create(:asset, user: user) }
    let!(:existing_version) {
      create(:asset_version, asset: existing_asset,
             properties: { "checksum_sha256" => checksum })
    }

    it "does not add the same member twice" do
      described_class.call(asset: asset, checksum: checksum, user: user)
      described_class.call(asset: asset, checksum: checksum, user: user)

      group = DuplicateGroup.where(checksum: checksum, status: "pending").last
      expect(group.duplicate_group_assets.count).to eq(2)
    end
  end
end
