# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiModelConfig, type: :model do
  subject(:config) { build(:ai_model_config) }

  describe "validations" do
    it "is valid with valid attributes" do
      expect(config).to be_valid
    end

    it "is invalid without a name" do
      config.name = nil
      expect(config).not_to be_valid
      expect(config.errors[:name]).to be_present
    end

    it "is invalid without a provider" do
      config.provider = nil
      expect(config).not_to be_valid
    end

    it "is invalid without a model_id" do
      config.model_id = nil
      expect(config).not_to be_valid
    end

    it "is invalid without a capability" do
      config.capability = nil
      expect(config).not_to be_valid
    end

    it "rejects unknown providers" do
      config.provider = "unknown_provider"
      expect(config).not_to be_valid
      expect(config.errors[:provider]).to be_present
    end

    it "rejects unknown capabilities" do
      config.capability = "telepathy"
      expect(config).not_to be_valid
    end

    it "rejects unknown health_status values" do
      config.health_status = "superb"
      expect(config).not_to be_valid
    end

    it "accepts all known providers" do
      AiModelConfig::PROVIDERS.each do |prov|
        config.provider = prov
        expect(config).to be_valid, "Expected valid for provider=#{prov}"
      end
    end
  end

  describe "scopes" do
    let!(:enabled_config)  { create(:ai_model_config, enabled: true) }
    let!(:disabled_config) { create(:ai_model_config, :disabled) }
    let!(:default_config)  { create(:ai_model_config, :default) }
    let!(:healthy_config)  { create(:ai_model_config, :healthy) }

    it ".enabled returns only enabled configs" do
      expect(AiModelConfig.enabled).to include(enabled_config, default_config, healthy_config)
      expect(AiModelConfig.enabled).not_to include(disabled_config)
    end

    it ".defaults returns only is_default configs" do
      expect(AiModelConfig.defaults).to include(default_config)
      expect(AiModelConfig.defaults).not_to include(enabled_config)
    end

    it ".for_capability filters by capability" do
      vision = create(:ai_model_config, :vision)
      expect(AiModelConfig.for_capability("vision")).to include(vision)
      expect(AiModelConfig.for_capability("generation")).not_to include(vision)
    end

    it ".healthy returns only healthy configs" do
      expect(AiModelConfig.healthy).to include(healthy_config)
      expect(AiModelConfig.healthy).not_to include(enabled_config)
    end
  end

  describe "#healthy?" do
    it "returns true for healthy status" do
      config.health_status = "healthy"
      expect(config.healthy?).to be true
    end

    it "returns false for other statuses" do
      %w[degraded unhealthy unknown].each do |s|
        config.health_status = s
        expect(config.healthy?).to be false
      end
    end
  end

  describe "#promote_to_default!" do
    let!(:existing_default) { create(:ai_model_config, capability: "generation", is_default: true) }
    let!(:another)          { create(:ai_model_config, capability: "generation", is_default: false) }

    it "sets is_default to true and demotes the previous default" do
      another.promote_to_default!
      expect(another.reload.is_default).to be true
      expect(existing_default.reload.is_default).to be false
    end

    it "does not affect models of a different capability" do
      embedding = create(:ai_model_config, :embedding, is_default: true)
      another.promote_to_default!
      expect(embedding.reload.is_default).to be true
    end
  end

  describe "after_commit broadcast" do
    it "publishes model.config.updated on save" do
      allow(Sidekiq).to receive(:redis).and_yield(double(publish: nil))
      create(:ai_model_config)
      expect(Sidekiq).to have_received(:redis)
    end
  end
end
