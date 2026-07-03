# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::AiModelConfigs", type: :request do
  let(:admin)   { create(:user, :admin) }
  let(:member)  { create(:user) }
  let(:headers) { { "Content-Type" => "application/json", "Accept" => "application/json" } }

  def auth_headers(user)
    sign_in user
    headers
  end

  describe "GET /api/v1/ai_model_configs" do
    before { create_list(:ai_model_config, 3) }

    context "as admin" do
      it "returns all configs" do
        get "/api/v1/ai_model_configs", headers: auth_headers(admin)
        expect(response).to have_http_status(:ok)
        expect(json["total"]).to eq(3)
        expect(json["configs"].length).to eq(3)
      end

      it "filters by capability" do
        create(:ai_model_config, :embedding)
        get "/api/v1/ai_model_configs?capability=embedding", headers: auth_headers(admin)
        expect(json["configs"].all? { |c| c["capability"] == "embedding" }).to be true
      end
    end

    context "as non-admin" do
      it "returns 403" do
        get "/api/v1/ai_model_configs", headers: auth_headers(member)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "unauthenticated" do
      it "returns 401" do
        get "/api/v1/ai_model_configs", headers: headers
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "GET /api/v1/ai_model_configs/capabilities" do
    it "returns capabilities, providers, health_statuses" do
      get "/api/v1/ai_model_configs/capabilities", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json["capabilities"]).to include("embedding", "generation")
      expect(json["providers"]).to include("openai")
    end
  end

  describe "GET /api/v1/ai_model_configs/:id" do
    let!(:config) { create(:ai_model_config, :healthy) }

    it "returns the requested config" do
      get "/api/v1/ai_model_configs/#{config.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(json).to include("id" => config.id, "health_status" => "healthy")
    end

    it "returns 404 for unknown configs" do
      get "/api/v1/ai_model_configs/999999", headers: auth_headers(admin)

      expect(response).to have_http_status(:not_found)
      expect(json).to eq("error" => "AI model config not found.")
    end
  end

  describe "POST /api/v1/ai_model_configs" do
    let(:valid_params) do
      { ai_model_config: { name: "Claude 3 Opus", provider: "anthropic", model_id: "claude-3-opus-20240229", capability: "generation" } }
    end

    it "creates a model config" do
      expect {
        post "/api/v1/ai_model_configs", params: valid_params.to_json, headers: auth_headers(admin)
      }.to change(AiModelConfig, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(json["name"]).to eq("Claude 3 Opus")
    end

    it "returns 422 for invalid params" do
      post "/api/v1/ai_model_configs", params: { ai_model_config: { name: "" } }.to_json, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/ai_model_configs/:id" do
    let!(:config) { create(:ai_model_config) }

    it "updates the config" do
      patch "/api/v1/ai_model_configs/#{config.id}",
            params: { ai_model_config: { name: "Updated Name" } }.to_json,
            headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json["name"]).to eq("Updated Name")
    end

    it "returns validation errors for invalid updates" do
      patch "/api/v1/ai_model_configs/#{config.id}",
            params: { ai_model_config: { name: "" } }.to_json,
            headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"]).to include("Name can't be blank")
    end
  end

  describe "DELETE /api/v1/ai_model_configs/:id" do
    let!(:config) { create(:ai_model_config) }

    it "deletes the config" do
      expect {
        delete "/api/v1/ai_model_configs/#{config.id}", headers: auth_headers(admin)
      }.to change(AiModelConfig, :count).by(-1)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/ai_model_configs/:id/health_check" do
    let!(:config) { create(:ai_model_config) }

    it "enqueues a health check worker" do
      expect(AiModelHealthCheckWorker).to receive(:perform_async).with(config.id)
      post "/api/v1/ai_model_configs/#{config.id}/health_check", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/ai_model_configs/:id/set_default" do
    let!(:existing_default) { create(:ai_model_config, capability: "generation", is_default: true) }
    let!(:config)           { create(:ai_model_config, capability: "generation") }

    it "promotes the config to default" do
      post "/api/v1/ai_model_configs/#{config.id}/set_default", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json["is_default"]).to be true
      expect(existing_default.reload.is_default).to be false
    end

    it "returns validation errors when promotion fails" do
      config.errors.add(:base, "cannot promote")
      allow_any_instance_of(AiModelConfig)
        .to receive(:promote_to_default!)
        .and_raise(ActiveRecord::RecordInvalid.new(config))

      post "/api/v1/ai_model_configs/#{config.id}/set_default", headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"]).to include("cannot promote")
    end
  end

  describe "POST /api/v1/ai_model_configs/:id/health_callback" do
    let!(:config) { create(:ai_model_config) }
    let(:gateway_secret) { "test-gateway-secret" }

    before do
      allow(Rails.application.credentials).to receive(:dig).with(:ai_gateway, :secret).and_return(gateway_secret)
    end

    it "updates health status with valid gateway secret" do
      post "/api/v1/ai_model_configs/#{config.id}/health_callback",
           params: { health: { health_status: "healthy", health_latency_ms: 95 } }.to_json,
           headers: headers.merge("X-Gateway-Secret" => gateway_secret)
      expect(response).to have_http_status(:ok)
      expect(config.reload.health_status).to eq("healthy")
      expect(config.reload.health_latency_ms).to eq(95)
    end

    it "returns 401 with wrong secret" do
      post "/api/v1/ai_model_configs/#{config.id}/health_callback",
           params: { health: { health_status: "healthy" } }.to_json,
           headers: headers.merge("X-Gateway-Secret" => "wrong-secret")
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns validation errors for invalid health updates" do
      post "/api/v1/ai_model_configs/#{config.id}/health_callback",
           params: { health: { health_status: "broken" } }.to_json,
           headers: headers.merge("X-Gateway-Secret" => gateway_secret)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"]).to include("Health status is not included in the list")
    end
  end

  private

  def json
    JSON.parse(response.body)
  end
end
