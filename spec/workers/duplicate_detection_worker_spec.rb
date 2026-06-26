require "rails_helper"

RSpec.describe DuplicateDetectionWorker, type: :worker do
  let(:user)     { create(:user) }
  let(:asset)    { create(:asset, user: user) }
  let(:checksum) { "abc123def456abc123def456abc123def456abc123def456abc123def456abc1" }

  before { Setting.set("duplicate_manager_enabled", true) }

  describe "#perform" do
    it "calls DuplicateDetectionService with correct args" do
      expect(DuplicateDetectionService).to receive(:call).with(
        asset:    asset,
        checksum: checksum,
        user:     user,
      ).and_return(
        DuplicateDetectionService::Result.new(
          duplicate_group: nil, new_duplicates: 0, enabled: true
        )
      )

      described_class.new.perform(asset.id, checksum, user.id)
    end

    it "does nothing when the asset is not found" do
      expect(DuplicateDetectionService).not_to receive(:call)
      expect {
        described_class.new.perform("non-existent-uuid", checksum, user.id)
      }.not_to raise_error
    end

    it "re-raises unexpected errors (so Sidekiq can retry)" do
      allow(DuplicateDetectionService).to receive(:call).and_raise(RuntimeError, "boom")
      expect {
        described_class.new.perform(asset.id, checksum, user.id)
      }.to raise_error(RuntimeError, "boom")
    end

    context "when a duplicate is detected" do
      let!(:existing_asset) { create(:asset) }
      let!(:existing_version) {
        create(:asset_version, asset: existing_asset,
               properties: { "checksum_sha256" => checksum })
      }

      it "creates a DuplicateGroup" do
        expect {
          described_class.new.perform(asset.id, checksum, user.id)
        }.to change(DuplicateGroup, :count).by(1)
      end
    end
  end

  describe "Sidekiq queue" do
    it "enqueues to the duplicate_detection queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("duplicate_detection")
    end
  end
end
