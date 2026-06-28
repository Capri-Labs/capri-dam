# frozen_string_literal: true

require "rails_helper"

RSpec.describe AssetProvenanceWorker, type: :worker do
  let(:redis) { instance_double("Redis") }

  before do
    allow(Sidekiq).to receive(:redis).and_yield(redis)
    allow(redis).to receive(:publish)
  end

  describe "#perform" do
    it "no-ops when the asset is not found" do
      expect { described_class.new.perform("non-existent-uuid") }.not_to raise_error
      expect(redis).not_to have_received(:publish)
    end

    it "no-ops when C2PA gateway integration is disabled" do
      asset = create(:asset)
      create(:c2pa_configuration, gateway_c2pa_enabled: false)
      described_class.new.perform(asset.id)
      # The c2pa_configuration create fires a broadcast; the worker itself
      # must NOT fire the asset.c2pa_verify event when gateway is disabled.
      expect(redis).not_to have_received(:publish).with("ai_gateway_events", include("asset.c2pa_verify"))
    end

    context "when gateway is enabled" do
      let!(:config) { create(:c2pa_configuration, :enabled) }
      let(:asset)   { create(:asset) }

      it "creates an unchecked placeholder record" do
        expect {
          described_class.new.perform(asset.id)
        }.to change(AssetProvenanceRecord, :count).by(1)
        expect(AssetProvenanceRecord.last.manifest_status).to eq("unchecked")
      end

      it "publishes an asset.c2pa_verify event to Redis" do
        described_class.new.perform(asset.id)
        expect(redis).to have_received(:publish).with("ai_gateway_events", include("asset.c2pa_verify"))
      end

      it "does not create a second record if one already exists" do
        create(:asset_provenance_record, :verified, asset: asset)
        expect {
          described_class.new.perform(asset.id)
        }.not_to change(AssetProvenanceRecord, :count)
      end

      it "re-raises errors so Sidekiq can retry" do
        allow(Sidekiq).to receive(:redis).and_raise(Redis::BaseError, "conn refused")
        expect { described_class.new.perform(asset.id) }.to raise_error(Redis::BaseError)
      end
    end
  end
end
