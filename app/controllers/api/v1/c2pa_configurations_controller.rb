# frozen_string_literal: true

# Singleton configuration for the organisation's C2PA / Content Provenance policy.
#
# | Method | Path                         | Auth  |
# |--------|------------------------------|-------|
# | GET    | /api/v1/c2pa_configuration   | admin |
# | PATCH  | /api/v1/c2pa_configuration   | admin |
#
# Saving broadcasts a `c2pa.config.updated` event to the AI Gateway via Redis.
class Api::V1::C2paConfigurationsController < ApplicationController
  before_action :authenticate_hybrid!
  before_action :require_admin!

  # GET /api/v1/c2pa_configuration
  def show
    render json: serialize(C2paConfiguration.current)
  end

  # PATCH /api/v1/c2pa_configuration
  def update
    config = C2paConfiguration.current
    if config.update(config_params)
      render json: { message: "C2PA policy saved.", config: serialize(config) }
    else
      render json: { errors: config.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def config_params
    params.require(:c2pa_configuration).permit(
      :gateway_c2pa_enabled, :auto_verify_on_ingest, :auto_sign_on_ingest,
      :require_c2pa_on_import, :ai_disclosure_required,
      :signing_issuer_name, :signing_org,
      :verification_strictness, :policy_notes,
      trust_store_urls: []
    )
  end

  def serialize(cfg)
    {
      id:                      cfg.id,
      gateway_c2pa_enabled:    cfg.gateway_c2pa_enabled,
      auto_verify_on_ingest:   cfg.auto_verify_on_ingest,
      auto_sign_on_ingest:     cfg.auto_sign_on_ingest,
      require_c2pa_on_import:  cfg.require_c2pa_on_import,
      ai_disclosure_required:  cfg.ai_disclosure_required,
      signing_issuer_name:     cfg.signing_issuer_name,
      signing_org:             cfg.signing_org,
      trust_store_urls:        cfg.trust_store_urls || [],
      verification_strictness: cfg.verification_strictness,
      policy_notes:            cfg.policy_notes,
      updated_at:              cfg.updated_at,
    }
  end
end
