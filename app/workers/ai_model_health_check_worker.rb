# frozen_string_literal: true

# Triggers the AI Gateway to report its current health for a specific model.
#
# The gateway responds by calling back:
#   POST /api/v1/ai_model_configs/:id/health_callback
#
# with { "health_status": "healthy|degraded|unhealthy", "latency_ms": 123 }.
#
# Idempotency: if the model no longer exists or is disabled, the worker no-ops.
#
# Scheduled via Sidekiq-Cron (see config/schedule.rb) — runs every 5 minutes
# for enabled models.
#
# @see AiModelConfig
# @see Api::V1::AiModelConfigsController#health_callback
class AiModelHealthCheckWorker
  include Sidekiq::Worker

  sidekiq_options queue: "smartai", retry: 2

  def perform(model_config_id)
    config = AiModelConfig.find_by(id: model_config_id)
    return unless config&.enabled?

    dispatch_health_ping(config)
  end

  private

  def dispatch_health_ping(config)
    base_url = ENV.fetch("APP_HOST_URL", "http://localhost:3000")
    callback = "#{base_url}/api/v1/ai_model_configs/#{config.id}/health_callback"

    payload = {
      event:        "model.health.check",
      model_id:     config.id,
      provider:     config.provider,
      model_ref:    config.model_id,
      capability:   config.capability,
      callback_url: callback,
    }.to_json

    Sidekiq.redis { |conn| conn.publish("ai_gateway_events", payload) }
  rescue StandardError => e
    Rails.logger.warn("[AiModelHealthCheck##{config.id}] dispatch skipped: #{e.message}")
  end
end
