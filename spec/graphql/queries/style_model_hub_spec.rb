# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GraphQL — Style & Model Hub queries", type: :request do
  let(:admin)  { create(:user, :admin) }
  let(:member) { build_stubbed(:user) }

  def gql(query, variables: {}, user: admin)
    sign_in user if user
    post "/graphql",
         params:  { query: query, variables: variables },
         headers: { "Accept" => "application/json" },
         as:      :json
    JSON.parse(response.body)
  end

  def schema_exec(query, variables: {}, context: {})
    HeadlessDamSchema.execute(query, variables: variables, context: context).to_h
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

    it "filters by enabled state" do
      create(:ai_model_config, :disabled, capability: "generation")

      result = gql(query.sub("query($capability: String)", "query($capability: String, $enabled: Boolean)")
                       .sub("aiModelConfigs(capability: $capability)", "aiModelConfigs(capability: $capability, enabled: $enabled)"),
                   variables: { enabled: false })

      expect(result.dig("data", "aiModelConfigs").map { |config| config["enabled"] }).to all(eq(false))
    end

    it "returns empty array for non-admin" do
      result = schema_exec(query, context: { current_user: member })
      expect(result.dig("data", "aiModelConfigs")).to eq([])
    end

    it "returns empty array when unauthenticated" do
      result = schema_exec(query, context: {})
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
      result = schema_exec(query, variables: { id: config.id }, context: { current_user: member })
      expect(result.dig("data", "aiModelConfig")).to be_nil
    end

    it "returns nil when unauthenticated" do
      result = schema_exec(query, variables: { id: config.id }, context: {})
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
      result = schema_exec(query, context: { current_user: member })
      expect(result.dig("data", "stylePresets")).to eq([])
    end

    it "returns empty when unauthenticated" do
      result = schema_exec(query, context: {})
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

    it "returns nil when unauthenticated" do
      result = schema_exec(query, variables: { id: preset.id }, context: {})
      expect(result.dig("data", "stylePreset")).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # createAiModelConfig mutation
  # ---------------------------------------------------------------------------

  describe "createAiModelConfig mutation" do
    # BaseMutation extends RelayClassicMutation → all arguments are wrapped
    # in a single `input:` argument as per the Relay Classic spec.
    let(:mutation) do
      <<~GQL
        mutation($input: CreateAiModelConfigInput!) {
          createAiModelConfig(input: $input) {
            aiModelConfig { id name capability }
            errors
          }
        }
      GQL
    end

    it "creates a model config" do
      result = gql(mutation, variables: { input: { name: "New Model", provider: "anthropic", modelId: "claude-3-haiku", capability: "generation" } })
      expect(result.dig("data", "createAiModelConfig", "errors")).to eq([])
      expect(result.dig("data", "createAiModelConfig", "aiModelConfig", "name")).to eq("New Model")
    end

    it "fails for non-admin" do
      result = schema_exec(mutation,
                           variables: { input: { name: "X", provider: "openai", modelId: "gpt-4", capability: "generation" } },
                           context: { current_user: member })
      expect(result["errors"]).not_to be_empty
    end

    it "fails when unauthenticated" do
      result = schema_exec(mutation,
                           variables: { input: { name: "Anon", provider: "openai", modelId: "gpt-4", capability: "generation" } },
                           context: {})

      expect(result["errors"].first["message"]).to include("Administrator privileges required")
    end

    it "returns validation errors for invalid configs" do
      result = gql(mutation, variables: { input: { name: "Broken", provider: "invalid", modelId: "gpt-4", capability: "generation" } })

      expect(result.dig("data", "createAiModelConfig", "aiModelConfig")).to be_nil
      expect(result.dig("data", "createAiModelConfig", "errors")).to include("Provider is not included in the list")
    end
  end

  # ---------------------------------------------------------------------------
  # createStylePreset mutation
  # ---------------------------------------------------------------------------

  describe "createStylePreset mutation" do
    let(:mutation) do
      <<~GQL
        mutation($input: CreateStylePresetInput!) {
          createStylePreset(input: $input) {
            stylePreset { id name slug }
            errors
          }
        }
      GQL
    end

    it "creates a style preset with auto-slug" do
      result = gql(mutation, variables: { input: { name: "Neon Night Market" } })
      expect(result.dig("data", "createStylePreset", "errors")).to eq([])
      expect(result.dig("data", "createStylePreset", "stylePreset", "slug")).to eq("neon-night-market")
    end

    it "fails when unauthenticated" do
      result = schema_exec(mutation, variables: { input: { name: "Anonymous Preset" } }, context: {})

      expect(result["errors"].first["message"]).to include("Administrator privileges required")
    end

    it "returns validation errors for invalid presets" do
      result = gql(mutation, variables: { input: { name: "" } })

      expect(result.dig("data", "createStylePreset", "stylePreset")).to be_nil
      expect(result.dig("data", "createStylePreset", "errors")).to include("Name can't be blank", "Slug can't be blank")
    end
  end
end
