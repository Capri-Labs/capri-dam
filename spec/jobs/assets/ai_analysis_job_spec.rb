# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assets::AiAnalysisJob, type: :job do
  before do
    allow(Redis).to receive(:new).and_return(instance_double(Redis, publish: true))
    allow_any_instance_of(AssetUrlHelper).to receive(:asset_url_for) { |_, asset| "/api/v1/assets/local/#{asset.uuid}" }
  end

  describe "#perform" do
    it "stores completed image analysis with labels, colors, tags, description, and similar assets" do
      folder = create(:folder)
      asset = create(:asset, title: "Blue Hero Image", folder: folder, properties: { "content_type" => "image/png" })
      create(:asset_version, asset: asset, properties: { "content_type" => "image/png" }).tap { |version| asset.update!(active_version: version) }
      similar = create(:asset, title: "Sibling", folder: folder, properties: { "content_type" => "image/jpeg" })
      create(:asset_version, asset: similar, properties: { "content_type" => "image/jpeg" }).tap { |version| similar.update!(active_version: version) }

      described_class.perform_now(asset.id)

      analysis = asset.reload.properties["ai_analysis"]
      expect(asset.properties["image_analysis_status"]).to eq("completed")
      expect(analysis["labels"]).to include("product", "blue", "hero")
      expect(analysis["colors"]).not_to be_empty
      expect(analysis["quality_score"]).to eq(91)
      expect(analysis["suggested_tags"]).to include("hero")
      expect(analysis["description"]).to include("image ready for cataloging")
      expect(analysis["similar_assets"].first).to include("id" => similar.id, "title" => "Sibling", "content_type" => "image/jpeg")
    end

    it "uses audio-specific defaults" do
      asset = create(:asset, title: "Podcast Intro", properties: { "content_type" => "audio/mpeg" })

      described_class.perform_now(asset.id)

      analysis = asset.reload.properties["ai_analysis"]
      expect(analysis["labels"]).to include("audio", "voice", "soundtrack")
      expect(analysis["suggested_tags"]).to include("audio", "podcast")
      expect(analysis["colors"]).to eq([])
      expect(analysis["quality_score"]).to eq(82)
      expect(analysis["description"]).to include("audio asset")
    end

    it "returns without error when the asset no longer exists" do
      expect { described_class.perform_now(SecureRandom.uuid) }.not_to raise_error
    end

    it "marks the asset as failed when analysis crashes" do
      asset = create(:asset, properties: { "content_type" => "application/pdf" })
      allow(described_class).to receive(:analysis_payload_for).and_raise(StandardError, "boom")

      expect(Rails.logger).to receive(:error).with(include("boom"))

      described_class.perform_now(asset.id)

      expect(asset.reload.properties["image_analysis_status"]).to eq("failed")
    end
  end

  describe ".analysis_payload_for" do
    it "builds document defaults for non-media content" do
      asset = build_stubbed(:asset, title: "Brand Guidelines", properties: { "content_type" => "application/pdf" })
      allow(asset).to receive(:active_version).and_return(nil)
      allow(asset).to receive(:folder_id).and_return(nil)

      payload = described_class.analysis_payload_for(asset)

      expect(payload[:labels]).to include("document", "brand", "archive")
      expect(payload[:quality_score]).to eq(78)
      expect(payload[:suggested_tags]).to include("document", "approved", "archive")
    end
  end
end
