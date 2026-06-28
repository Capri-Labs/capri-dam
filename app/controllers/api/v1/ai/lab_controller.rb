# frozen_string_literal: true

# Provides the backend for the Prompt Playground UI at /ai/lab/playground.
# All requests are proxied to the AI Gateway via Faraday; we never store
# prompt bodies or raw completion text here — only token metrics get written
# to the audit log (future work).
#
# Routes:
#   GET  /api/v1/ai/lab/models  →  #models
#   POST /api/v1/ai/lab/chat    →  #chat
class Api::V1::Ai::LabController < ApplicationController
  before_action :authenticate_hybrid!
  before_action :require_admin!

  PROVIDER_MODELS = {
    "openai"    => %w[gpt-4o gpt-4o-mini gpt-4-turbo gpt-3.5-turbo],
    "anthropic" => %w[claude-3-5-sonnet-20241022 claude-3-haiku-20240307],
    "local"     => %w[llama-3-local mistral-local phi-3-mini],
  }.freeze

  # GET /api/v1/ai/lab/models
  # Returns the active provider + model list so the UI can pre-populate the
  # model selector without hard-coding provider info in the frontend.
  def models
    config = AiConfiguration.current
    render json: {
      active_provider: config.active_provider,
      default_model:   config.generation_model,
      models:          PROVIDER_MODELS.fetch(config.active_provider, []),
      all_providers:   PROVIDER_MODELS,
    }
  end

  # POST /api/v1/ai/lab/chat
  # Body params:
  #   messages     – Array<{role: "system"|"user"|"assistant", content: String}>
  #   model        – (optional) override the default model
  #   temperature  – Float 0.0–2.0 (default 0.7)
  #   max_tokens   – Integer (default 1024)
  #   stream       – Boolean — reserved; not yet supported
  def chat
    messages    = params.require(:messages)
    config      = AiConfiguration.current
    model       = params.fetch(:model, config.generation_model)
    temperature = params.fetch(:temperature, 0.7).to_f.clamp(0.0, 2.0)
    max_tokens  = params.fetch(:max_tokens, 1024).to_i.clamp(1, 8192)

    response = gateway_client.post("/v1/chat") do |req|
      req.body = {
        messages:    messages,
        model:       model,
        temperature: temperature,
        max_tokens:  max_tokens,
      }
    end

    if response.success?
      render json: response.body, status: :ok
    else
      render json: {
        error: response.body.is_a?(Hash) ? response.body["detail"] : "AI Gateway returned #{response.status}",
      }, status: response.status
    end
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    render json: { error: "AI Gateway unavailable: #{e.message}" }, status: :service_unavailable
  rescue Faraday::Error => e
    Rails.logger.error("[AiLab#chat] Faraday error: #{e.message}")
    render json: { error: "Failed to reach AI Gateway" }, status: :bad_gateway
  end

  private

  def gateway_client
    @gateway_client ||= Faraday.new(url: ai_gateway_url) do |conn|
      conn.request  :json
      conn.response :json
      conn.options.timeout      = 60
      conn.options.open_timeout = 5
      conn.adapter Faraday.default_adapter
    end
  end

  def ai_gateway_url
    Rails.application.credentials.dig(:ai_gateway, :url).presence ||
      ENV.fetch("AI_GATEWAY_URL", "http://localhost:8000")
  end
end
