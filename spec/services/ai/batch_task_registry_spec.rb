# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::BatchTaskRegistry do
  before do
    allow(Redis).to receive(:new).and_return(instance_double(Redis, publish: true))
  end

  describe ".tasks and .scopes" do
    it "exposes immutable task and scope descriptors" do
      expect(described_class.tasks.map(&:key)).to include("metadata_extraction", "embedding_backfill", "style_audit")
      expect(described_class.scopes.map(&:key)).to include("all_assets", "missing_embeddings", "style_untagged")
      expect(described_class::COST_TIERS).to contain_exactly("low", "medium", "high")
    end
  end

  describe ".task_keys and .scope_keys" do
    it "returns serializable keys" do
      expect(described_class.task_keys).to all(be_a(String))
      expect(described_class.scope_keys).to all(be_a(String))
      expect(described_class.task_keys).to include("c2pa_verify")
      expect(described_class.scope_keys).to include("unsigned_assets")
    end
  end

  describe ".task and .scope" do
    it "finds descriptors by string-like key" do
      task = described_class.task(:visual_context)
      scope = described_class.scope(:all_images)

      expect(task.label).to eq("Deep Visual Context")
      expect(task.gateway_capability).to eq("vision.describe")
      expect(scope.label).to eq("All Images")
    end

    it "returns nil for unknown descriptors" do
      expect(described_class.task("missing")).to be_nil
      expect(described_class.scope("missing")).to be_nil
    end
  end

  describe ".resolve_targets" do
    let!(:image_with_embedding) do
      asset = create(:asset, status: :ready, properties: { "content_type" => "image/png", "tags" => [] })
      asset.create_asset_embedding!(embedding: Array.new(1536, 0.001), model_name: "text-embedding-3-small")
      asset
    end
    let!(:image_without_embedding) { create(:asset, status: :ready, properties: { "content_type" => "image/jpeg", "tags" => [] }) }
    let!(:described_asset) { create(:asset, status: :ready, properties: { "description" => "Done", "tags" => [ { "type" => "style_preset" } ] }) }

    before do
      allow(SmartCollectionRouterWorker).to receive(:perform_async)
    end

    it "resolves known scopes with their database filters" do
      expect(described_class.resolve_targets("all_images")).to include(image_with_embedding, image_without_embedding)
      expect(described_class.resolve_targets("missing_embeddings")).to include(image_without_embedding)
      expect(described_class.resolve_targets("missing_embeddings")).not_to include(image_with_embedding)
      expect(described_class.resolve_targets("missing_metadata")).to include(image_without_embedding)
      expect(described_class.resolve_targets("missing_metadata")).not_to include(described_asset)
    end

    it "returns an empty relation for unknown scopes" do
      expect(described_class.resolve_targets("unknown")).to be_empty
    end

    it "resolves tag, provenance, signing, and style-specific scopes" do
      untagged = create(:asset, status: :ready, properties: { "content_type" => "application/pdf", "tags" => [] })
      tagged = create(:asset, status: :ready, properties: { "content_type" => "image/png", "tags" => [ { "type" => "style_preset" } ] })
      invalid = create(:asset, status: :ready)
      ai_modified = create(:asset, status: :ready)
      signed = create(:asset, status: :ready)
      unchecked = create(:asset, status: :ready)
      create(:asset_provenance_record, :invalid, asset: invalid)
      create(:asset_provenance_record, :ai_modified, asset: ai_modified)
      create(:asset_provenance_record, :signed, asset: signed)
      create(:asset_provenance_record, asset: unchecked)

      expect(described_class.resolve_targets(:missing_tags)).to include(untagged)
      expect(described_class.resolve_targets(:style_untagged)).to include(untagged)
      expect(described_class.resolve_targets(:style_untagged)).not_to include(tagged)
      expect(described_class.resolve_targets(:invalid_manifests)).to contain_exactly(invalid)
      expect(described_class.resolve_targets(:ai_modified_assets)).to contain_exactly(ai_modified)
      expect(described_class.resolve_targets(:unsigned_assets)).to include(untagged, invalid, ai_modified, unchecked)
      expect(described_class.resolve_targets(:unsigned_assets)).not_to include(signed)
      expect(described_class.resolve_targets(:unverified_assets)).to include(untagged, unchecked)
      expect(described_class.resolve_targets(:unverified_assets)).not_to include(invalid, ai_modified, signed)
    end
  end

  describe ".as_json_meta" do
    it "returns frontend metadata without resolver lambdas" do
      meta = described_class.as_json_meta

      expect(meta[:tasks].first).to include(:key, :label, :description, :cost_tier, :default_tools, :gateway_capability)
      expect(meta[:scopes].first).to include(:key, :label, :description)
      expect(meta[:scopes].first).not_to have_key(:resolver)
    end

    it "serializes every registered task and scope" do
      meta = described_class.as_json_meta

      expect(meta[:tasks].map { |task| task[:key] }).to eq(described_class.task_keys)
      expect(meta[:scopes].map { |scope| scope[:key] }).to eq(described_class.scope_keys)
    end
  end
end
