# frozen_string_literal: true

# Dispatches an {AiTaggingRun} to the AI Gateway.
#
# Kept deliberately thin, mirroring {AiReviewWorker}: all inference happens in
# the gateway. This worker marks the run +running+ and publishes a single
# `ai_tagging.dispatch` event over Redis. The gateway fetches the media, runs
# the vision model, and posts labels back to
# POST /api/v1/ai_tagging_runs/:id/suggestions (gateway-secret authenticated).
#
# Idempotency: no-ops unless the run is still +queued+, so a Sidekiq retry
# cannot dispatch the same run twice and duplicate every suggestion.
#
# @see AiTaggingRun
# @see Api::V1::AiTaggingRunsController
class AiAutoTagWorker
  include Sidekiq::Worker

  sidekiq_options queue: "smartai", retry: 3

  def perform(run_id)
    run = AiTaggingRun.find_by(id: run_id)
    return unless run&.status == "queued"

    run.start!
    broadcast_to_gateway(run)
  rescue StandardError => e
    run&.fail!(e.message)
    raise
  end

  private

  def broadcast_to_gateway(run)
    payload = run.to_gateway_payload.to_json
    Sidekiq.redis { |conn| conn.publish("ai_gateway_events", payload) }
  rescue StandardError => e
    # A gateway that is down should leave the run visibly failed rather than
    # stuck in +running+ forever, where a curator would wait for suggestions
    # that are never coming.
    run.fail!("Gateway dispatch failed: #{e.message}")
    Rails.logger.warn("[AiTaggingRun##{run.id}] gateway dispatch failed: #{e.message}")
  end
end
