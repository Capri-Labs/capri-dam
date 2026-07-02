# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::Lab coverage", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }
  let(:gateway_url) { "http://localhost:8000" }

  before do
    sign_in admin
    allow(Sidekiq).to receive(:redis).and_yield(instance_double("Redis", publish: true))
    AiConfiguration.current.update!(active_provider: "anthropic", generation_model: "claude-3-haiku-20240307")
  end

  describe "GET /api/v1/ai/lab/models" do
    it "returns the active provider, default model, and provider map" do
      get "/api/v1/ai/lab/models", as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["active_provider"]).to eq("anthropic")
      expect(json["models"]).to include("claude-3-haiku-20240307")
      expect(json["all_providers"]).to include("openai", "anthropic", "local")
    end

    it "forbids non-admin users" do
      sign_out admin
      sign_in user

      get "/api/v1/ai/lab/models", as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/ai/lab/chat" do
    it "proxies chat requests with clamped generation parameters" do
      chat_request = stub_request(:post, "#{gateway_url}/v1/chat")
        .to_return(status: 200, body: { "choices" => [ { "message" => { "content" => "Hi" } } ] }.to_json, headers: { "Content-Type" => "application/json" })

      post "/api/v1/ai/lab/chat", params: {
        messages: [ { role: "user", content: "Hello" } ],
        model: "gpt-4o-mini",
        temperature: 9,
        max_tokens: 0,
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(chat_request).to have_been_requested
      request_body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
      expect(request_body).to include("model" => "gpt-4o-mini", "temperature" => 2.0, "max_tokens" => 1)
      expect(JSON.parse(response.body).dig("choices", 0, "message", "content")).to eq("Hi")
    end

    it "returns gateway validation errors" do
      stub_request(:post, "#{gateway_url}/v1/chat")
        .to_return(status: 422, body: { detail: "invalid prompt" }.to_json, headers: { "Content-Type" => "application/json" })

      post "/api/v1/ai/lab/chat", params: { messages: [ { role: "user", content: "Hello" } ] }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to eq("invalid prompt")
    end

    it "returns 503 when the gateway is unavailable" do
      stub_request(:post, "#{gateway_url}/v1/chat").to_timeout

      post "/api/v1/ai/lab/chat", params: { messages: [ { role: "user", content: "Hello" } ] }, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body)["error"]).to include("AI Gateway unavailable")
    end

    it "returns 401 when unauthenticated" do
      sign_out admin

      post "/api/v1/ai/lab/chat", params: { messages: [ { role: "user", content: "Hello" } ] }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
