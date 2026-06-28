# frozen_string_literal: true

# Publishes a single-asset C2PA verification request to the AI Gateway over
# Redis.  Used for individual asset verification (e.g. after ingest when
# +C2paConfiguration#auto_verify_on_ingest+ is enabled).
#
# For bulk verification across the whole library use the **C2PA Verification**
# batch task from the /ai/governance/provenance screen — that goes through
# {AiBatchJobWorker} which dispatches a single large batch event and the
# gateway pages through the targets itself.
#
# == Callback
#
# The gateway processes the asset and calls back with the result via
# POST /api/v1/asset_provenance_records/bulk_upsert (single-element array).
#
# @see C2paConfiguration
# @see AssetProvenanceRecord
# @see Api::V1::AssetProvenanceRecordsController#bulk_upsert
class AssetProvenanceWorker
  include Sidekiq::Worker

  sidekiq_options queue: "smartai", retry: 3

  def perform(asset_id)
    asset  = Asset.find_by(id: asset_id)
    return unless asset

    config = C2paConfiguration.current
    return unless config.gateway_c2pa_enabled?

    # Create or touch the placeholder record so the UI shows the asset
    # as "unchecked" / in-progress immediately.
    record = AssetProvenanceRecord.find_or_initialize_by(asset_id: asset.id)
    record.manifest_status = "unchecked" if record.new_record?
    record.save!

    # Fire-and-forget: gateway processes the asset and calls bulk_upsert
    payload = {
      event:    "asset.c2pa_verify",
      asset_id: asset.uuid,
      options:  {
        strictness:             config.verification_strictness,
        ai_disclosure_required: config.ai_disclosure_required?,
        signing_enabled:        config.auto_sign_on_ingest?,
      },
    }.to_json

    Sidekiq.redis { |conn| conn.publish("ai_gateway_events", payload) }
  rescue StandardError => e
    Rails.logger.error("[AssetProvenanceWorker] asset=#{asset_id} error=#{e.message}")
    raise
  end
end
