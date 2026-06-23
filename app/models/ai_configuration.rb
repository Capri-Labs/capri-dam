class AiConfiguration < ApplicationRecord
  # Ensure there is always only one global configuration record
  validates :active_provider, presence: true

  after_commit :broadcast_configuration_update, on: [:create, :update]

  def self.current
    first_or_create!(
      active_provider: 'openai',
      generation_model: 'gpt-4o',
      embedding_model: 'text-embedding-3-small',
      monthly_budget_usd: 100.0,
      current_spend_usd: 0.0,
      system_prompt: 'You are an enterprise data steward...',
      fallback_to_local: true
    )
  end

  private

  def broadcast_configuration_update
    payload = {
      event: 'gateway.config.updated',
      config: self.as_json
    }.to_json

    # Python LangChain agent will listen to this and swap models on the fly.
    # Best-effort: a downed/unavailable Redis must never roll back a config save.
    Sidekiq.redis { |conn| conn.publish('ai_gateway_events', payload) }
  rescue StandardError => e
    Rails.logger.warn("[AiConfiguration##{id}] config broadcast skipped: #{e.message}")
  end
end