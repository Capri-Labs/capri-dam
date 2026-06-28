# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GraphQL — Style & Model Hub queries", type: :request do
  let(:admin)  { create(:user, :admin) }
  let(:member) { create(:user) }

  def gql(query, variables: {}, user: admin)
    sign_in user if user
    post "/graphql",
         params:  { query: query, variables: variables.to_json }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    JSON.parse(response.body)
  end

  # ---------------------------------------------------------------------------
  # aiModelConfigs
  # ---------------------------------------------------------------------------

  describe "aiModelConfigs" do
    let!(:gen_config)   { create(:ai_model_config, capability: "generation") }
    let!(:embed_config) { create(:ai_model_config, :embedding) }

    let(:query) do
      <<~GQL
        query($capability: String) {
          aiModelConfigs(capability: $capability) {
            id name provider modelId capability enabled isDefault healthStatus
          }
        }
      GQL
    end

    it "returns all model configs for admin" do
      result = gql(query)
      ids = result.dig("data", "aiModelConfigs").map { |c| c["id"].to_i }
      expect(ids).to include(gen_config.id, embed_config.id)
    end

    it "filters by capability" do
      result = gql(query, variables: { capability: "embedding" })
      caps = result.dig("data", "aiModelConfigs").map { |c| c["capability"] }
      expect(caps).to all(eq("embedding"))
    end

    it "returns empty array for non-admin" do
      result = gql(query, user: member)
      expect(result.dig("data", "aiModelConfigs")).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # aiModelConfig (single)
  # ---------------------------------------------------------------------------

  describe "aiModelConfig" do
    let!(:config) { create(:ai_model_config, :healthy) }

    let(:query) do
      <<~GQL
        query($id: ID!) {
          aiModelConfig(id: $id) {
            id name healthStatus healthLatencyMs
          }
        }
      GQL
    end

    it "returns the model config" do
      result = gql(query, variables: { id: config.id })
      expect(result.dig("data", "aiModelConfig", "id").to_i).to eq(config.id)
      expect(result.dig("data", "aiModelConfig", "healthStatus")).to eq("healthy")
    end

    it "returns nil for non-admin" do
      result = gql(query, variables: { id: config.id }, user: member)
      expect(result.dig("data", "aiModelConfig")).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # stylePresets
  # ---------------------------------------------------------------------------

  describe "stylePresets" do
    let!(:active_preset)   { create(:style_preset, active: true) }
    let!(:inactive_preset) { create(:style_preset, :inactive) }

    let(:query) do
      <<~GQL
        query($active: Boolean) {
          stylePresets(active: $active) {
            id name slug active isDefault stale
          }
        }
      GQL
    end

    it "returns all presets for admin" do
      result = gql(query)
      ids = result.dig("data", "stylePresets").map { |p| p["id"].to_i }
      expect(ids).to include(active_preset.id, inactive_preset.id)
    end

    it "filters by active" do
      result = gql(query, variables: { active: true })
      ids = result.dig("data", "stylePresets").map { |p| p["id"].to_i }
      expect(ids).to include(active_preset.id)
      expect(ids).not_to include(inactive_preset.id)
    end

    it "returns empty for non-admin" do
      result = gql(query, user: member)
      expect(result.dig("data", "stylePresets")).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # stylePreset (single)
  # ---------------------------------------------------------------------------

  describe "stylePreset" do
    let!(:preset) { create(:style_preset, :synced) }

    let(:query) do
      <<~GQL
        query($id: ID!) {
          stylePreset(id: $id) {
            id name slug gatewayRef syncedAt stale
          }
        }
      GQL
    end

    it "returns the preset" do
      result = gql(query, variables: { id: preset.id })
      expect(result.dig("data", "stylePreset", "id").to_i).to eq(preset.id)
      expect(result.dig("data", "stylePreset", "gatewayRef")).to eq(preset.gateway_ref)
    end
  end

  # ---------------------------------------------------------------------------
  # createAiModelConfig mutation
  # ---------------------------------------------------------------------------

  describe "createAiModelConfig mutation" do
    let(:mutation) do
      <<~GQL
        mutation($name: String!, $provider: String!, $modelId: String!, $capability: String!) {
          createAiModelConfig(name: $name, provider: $provider, modelId: $modelId, capability: $capability) {
            aiModelConfig { id name capability }
            errors
          }
        }
      GQL
    end

    it "creates a model config" do
      result = gql(mutation, variables: { name: "New Model", provider: "anthropic", modelId: "claude-3-haiku", capability: "generation" })
      expect(result.dig("data", "createAiModelConfig", "errors")).to eq([])
      expect(result.dig("data", "createAiModelConfig", "aiModelConfig", "name")).to eq("New Model")
    end

    it "fails for non-admin" do
      result = gql(mutation, variables: { name: "X", provider: "openai", modelId: "gpt-4", capability: "generation" }, user: member)
      expect(result["errors"]).not_to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # createStylePreset mutation
  # ---------------------------------------------------------------------------

  describe "createStylePreset mutation" do
    let(:mutation) do
      <<~GQL
        mutation($name: String!) {
          createStylePreset(name: $name) {
            stylePreset { id name slug }
            errors
          }
        }
      GQL
    end

    it "creates a style preset with auto-slug" do
      result = gql(mutation, variables: { name: "Neon Night Market" })
      expect(result.dig("data", "createStylePreset", "errors")).to eq([])
      expect(result.dig("data", "createStylePreset", "stylePreset", "slug")).to eq("neon-night-market")
    end
  end
end
