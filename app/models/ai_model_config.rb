# frozen_string_literal: true

# Represents a single AI model endpoint registered for use with the Capri DAM gateway.
#
# == Capabilities
# Each model is tagged with a +capability+ that determines its role:
#   * +embedding+       — vector embedding (Semantic Copilot, backfill batch)
#   * +generation+      — text/image generation (Prompt Playground, agent tools)
#   * +vision+          — image analysis / description (visual_context batch task)
#   * +style_transfer+  — style-guided generation (Style & Model Hub batch tasks)
#   * +audio+           — audio transcription / synthesis
#
# == Health tracking
# Gateway health-check results are written back via the
# POST /api/v1/ai_model_configs/:id/health_callback endpoint.
#
# == Broadcasting
# Every save publishes a +model.config.updated+ event on the
# +ai_gateway_events+ Redis channel so the gateway can hot-reload its
# model routing table without a restart.
#
# @see Api::V1::AiModelConfigsController
# @see AiModelHealthCheckWorker
class AiModelConfig < ApplicationRecord
  PROVIDERS   = %w[openai anthropic ollama huggingface azure_openai custom].freeze
  CAPABILITIES = %w[embedding generation vision style_transfer audio].freeze
  HEALTH_STATUSES = %w[healthy degraded unhealthy unknown].freeze

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  # No direct model associations; the UI controller joins via created_by on
  # StylePreset, not AiModelConfig.

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :name,       presence: true, length: { maximum: 120 }
  validates :provider,   presence: true, inclusion: { in: PROVIDERS }
  validates :model_id,   presence: true, length: { maximum: 200 }
  validates :capability, presence: true, inclusion: { in: CAPABILITIES }
  validates :health_status, inclusion: { in: HEALTH_STATUSES }

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  scope :enabled,     -> { where(enabled: true) }
  scope :defaults,    -> { where(is_default: true) }
  scope :for_capability, ->(cap) { where(capability: cap.to_s) }
  scope :healthy,     -> { where(health_status: "healthy") }
  scope :by_provider, ->(prov) { where(provider: prov.to_s) }
  scope :recent,      -> { order(created_at: :desc) }

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  after_commit :broadcast_config_update, on: %i[create update]

  # ---------------------------------------------------------------------------
  # Instance helpers
  # ---------------------------------------------------------------------------

  # @return [Boolean]
  def healthy?
    health_status == "healthy"
  end

  # Promotes this model to the default for its capability and demotes any
  # previous default (single transaction).
  def promote_to_default!
    transaction do
      AiModelConfig.where(capability: capability, is_default: true)
                   .where.not(id: id)
                   .update_all(is_default: false)
      update!(is_default: true)
    end
  end

  private

  def broadcast_config_update
    payload = {
      event:  "model.config.updated",
      config: {
        id:          id,
        name:        name,
        provider:    provider,
        model_id:    model_id,
        capability:  capability,
        enabled:     enabled,
        is_default:  is_default,
        config_params: config_params,
      },
    }.to_json

    Sidekiq.redis { |conn| conn.publish("ai_gateway_events", payload) }
  rescue StandardError => e
    Rails.logger.warn("[AiModelConfig##{id}] config broadcast skipped: #{e.message}")
  end
end
