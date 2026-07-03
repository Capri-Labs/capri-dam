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

  context "when duplicate processing raises an error" do
    let!(:existing_asset) do
      create(:asset, user: user).tap do |record|
        create(:asset_version, asset: record, properties: { "checksum_sha256" => checksum })
      end
    end

    before { allow(Rails.logger).to receive(:error) }

    it "returns a safe result when the asset is missing" do
      result = described_class.call(asset: nil, checksum: checksum, user: user)

      expect(result.duplicate_detected?).to be(false)
      expect(result.enabled).to be(true)
      expect(Rails.logger).to have_received(:error).with(include("Error for asset :"))
    end

    it "returns a safe result when group creation fails for a real asset" do
      allow(DuplicateGroup).to receive(:find_or_initialize_by).and_raise(StandardError, "boom")

      result = described_class.call(asset: asset, checksum: checksum, user: user)

      expect(result.duplicate_detected?).to be(false)
      expect(result.enabled).to be(true)
      expect(Rails.logger).to have_received(:error).with(include("Error for asset #{asset.id}: StandardError: boom"))
    end
  end

  describe "private helper branches" do
    let(:service) { described_class.new(asset: asset, checksum: checksum, user: user) }

    it "leaves empty duplicate groups untouched when there is no oldest asset" do
      group = create(:duplicate_group, checksum: checksum, status: "pending")

      expect { service.send(:mark_original, group) }.not_to raise_error
      expect(group.duplicate_group_assets.reload).to be_empty
    end

    it "returns early when there is no user to notify" do
      silent_service = described_class.new(asset: asset, checksum: checksum, user: nil)

      expect {
        silent_service.send(:send_inbox_notification, create(:duplicate_group, total_count: 2))
      }.not_to change(Notification, :count)
    end

    it "logs notification failures for real users without raising" do
      allow(Notification).to receive(:create!).and_raise(StandardError, "inbox down")
      allow(Rails.logger).to receive(:warn)

      expect {
        service.send(:send_inbox_notification, create(:duplicate_group, total_count: 2))
      }.not_to raise_error

      expect(Rails.logger).to have_received(:warn).with(include("Notification failed for user #{user.id}: inbox down"))
    end
  end
end
