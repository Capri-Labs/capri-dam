# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::BatchTaskRegistry do
  describe ".tasks" do
    it "returns frozen task descriptors with required attributes" do
      expect(described_class.tasks).to all(respond_to(:key, :label, :gateway_capability))
      expect(described_class.task_keys).to include("metadata_extraction", "embedding_backfill")
    end

    it "uses only known cost tiers" do
      described_class.tasks.each do |task|
        expect(described_class::COST_TIERS).to include(task.cost_tier)
      end
    end
  end

  describe ".task" do
    it "finds a task by key" do
      expect(described_class.task("seo_enrichment").label).to eq("SEO Enrichment")
    end

    it "returns nil for an unknown key" do
      expect(described_class.task("nope")).to be_nil
    end
  end

  describe ".scope / .scopes" do
    it "exposes the registered dataset keys" do
      expect(described_class.scope_keys).to include("all_assets", "missing_embeddings")
    end

    it "finds a scope by key" do
      expect(described_class.scope("all_assets").label).to eq("All Assets")
    end
  end

  describe ".resolve_targets" do
    it "returns the assets relation for a valid scope" do
      a = create(:asset)
      create(:asset, :trashed)
      expect(described_class.resolve_targets("all_assets")).to include(a)
      expect(described_class.resolve_targets("all_assets").count).to eq(1)
    end

    it "returns an empty relation for an unknown scope" do
      create(:asset)
      expect(described_class.resolve_targets("nowhere")).to be_empty
    end
  end

  describe ".as_json_meta" do
    it "serialises tasks and scopes for the UI" do
      meta = described_class.as_json_meta
      expect(meta[:tasks].first.keys).to include(:key, :label, :cost_tier, :gateway_capability)
      expect(meta[:scopes].first.keys).to include(:key, :label, :description)
    end
  end
end
