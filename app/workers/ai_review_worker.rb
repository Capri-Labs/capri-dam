# frozen_string_literal: true

# Dispatches an {AiReview} to the AI Gateway.
#
# Kept deliberately thin, mirroring {AiBatchJobWorker}: all inference happens in
# the gateway. This worker marks the run +running+ and publishes a single
# `ai_review.dispatch` event over Redis. The gateway fetches the media, runs the
# vision model, and posts findings back to
# POST /api/v1/ai_reviews/:id/findings (gateway-secret authenticated).
#
# Idempotency: no-ops unless the run is still +queued+, so a Sidekiq retry
# cannot dispatch the same review twice and duplicate every finding.
#
# @see AiReview
# @see Api::V1::AiReviewsController
class AiReviewWorker
  include Sidekiq::Worker

  sidekiq_options queue: "smartai", retry: 3

  def perform(review_id)
    review = AiReview.find_by(id: review_id)
    return unless review&.status == "queued"

    review.start!
    broadcast_to_gateway(review)
  rescue StandardError => e
    review&.fail!(e.message)
    raise
  end

  private

  def broadcast_to_gateway(review)
    payload = review.to_gateway_payload.to_json
    Sidekiq.redis { |conn| conn.publish("ai_gateway_events", payload) }
  rescue StandardError => e
    # A gateway that is down should leave the run visibly failed rather than
    # stuck in +running+ forever, where a reviewer would wait for findings that
    # are never coming.
    review.fail!("Gateway dispatch failed: #{e.message}")
    Rails.logger.warn("[AiReview##{review.id}] gateway dispatch failed: #{e.message}")
  end
end
