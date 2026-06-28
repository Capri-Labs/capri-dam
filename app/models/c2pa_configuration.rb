# frozen_string_literal: true

# Singleton configuration record for the organisation's C2PA / Content Provenance
# policy.  Use {C2paConfiguration.current} — never query directly.
#
# == Broadcasting
#
# Every save publishes a `c2pa.config.updated` event on the `ai_gateway_events`
# Redis channel so the AI Gateway can hot-swap verification parameters without
# a restart.
#
# @see Api::V1::C2paConfigurationController
class C2paConfiguration < ApplicationRecord
  VERIFICATION_STRICTNESS = %w[lenient strict].freeze

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :verification_strictness,
            presence: true,
            inclusion: { in: VERIFICATION_STRICTNESS }

  # ---------------------------------------------------------------------------
  # Singleton accessor
  # ---------------------------------------------------------------------------

  # @return [C2paConfiguration] the single global config row (created with
  #   safe defaults on first call)
  def self.current
    first_or_create!(
      gateway_c2pa_enabled:    false,
      auto_verify_on_ingest:   false,
      auto_sign_on_ingest:     false,
      require_c2pa_on_import:  false,
      ai_disclosure_required:  true,
      trust_store_urls:        [],
      verification_strictness: "lenient"
    )
  end

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  after_commit :broadcast_config_update, on: %i[create update]

  private

  def broadcast_config_update
    payload = {
      event: "c2pa.config.updated",
      config: {
        gateway_c2pa_enabled:    gateway_c2pa_enabled,
        auto_verify_on_ingest:   auto_verify_on_ingest,
        auto_sign_on_ingest:     auto_sign_on_ingest,
        ai_disclosure_required:  ai_disclosure_required,
        signing_issuer_name:     signing_issuer_name,
        signing_org:             signing_org,
        trust_store_urls:        trust_store_urls || [],
        verification_strictness: verification_strictness,
      },
    }.to_json

    Sidekiq.redis { |conn| conn.publish("ai_gateway_events", payload) }
  rescue StandardError => e
    Rails.logger.warn("[C2paConfiguration##{id}] config broadcast skipped: #{e.message}")
  end
end
