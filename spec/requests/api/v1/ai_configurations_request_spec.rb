# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::AiConfigurations coverage", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  before do
    sign_in admin
    allow(Sidekiq).to receive(:redis).and_yield(instance_double("Redis", publish: true))
  end

  describe "GET /api/v1/ai_configuration" do
    it "returns the singleton configuration" do
      AiConfiguration.current.update!(active_provider: "local", generation_model: "llama-3-local")

      get "/api/v1/ai_configuration", as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("active_provider" => "local", "generation_model" => "llama-3-local")
    end

    it "requires authentication" do
      sign_out admin

      get "/api/v1/ai_configuration", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/ai_configuration" do
    it "updates valid admin configuration changes" do
      patch "/api/v1/ai_configuration", params: {
        ai_configuration: {
          active_provider: "openai",
          generation_model: "gpt-4o-mini",
          embedding_model: "text-embedding-3-small",
          monthly_budget_usd: 250.50,
          fallback_to_local: false,
          system_prompt: "Catalog precisely",
        },
      }, as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["message"]).to include("synchronized")
      expect(json.dig("config", "generation_model")).to eq("gpt-4o-mini")
      expect(AiConfiguration.current.reload.fallback_to_local).to be(false)
    end

    it "returns validation errors for invalid configuration" do
      patch "/api/v1/ai_configuration", params: { ai_configuration: { active_provider: "" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"].join).to include("Active provider")
    end

    it "forbids non-admin updates" do
      sign_out admin
      sign_in user

      patch "/api/v1/ai_configuration", params: { ai_configuration: { active_provider: "local" } }, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
