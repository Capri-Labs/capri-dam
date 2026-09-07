# Delivers one review event to one subscribed endpoint.
#
# ONE JOB PER SUBSCRIPTION, NOT PER EVENT
# ---------------------------------------
# A single comment may interest several endpoints. Fanning out into one job per
# (event, subscription) pair means a slow or dead receiver delays only its own
# delivery — batching them into one job would let the worst endpoint set the
# pace for all of them, and a retry would re-deliver to endpoints that had
# already succeeded.
#
# THE PAYLOAD IS BUILT HERE, NOT PASSED IN
# ----------------------------------------
# Only identifiers are enqueued. Sidekiq arguments are JSON in Redis, and
# serialising a whole comment into the queue would both bloat it and freeze a
# snapshot that may be stale or, worse, may include text the author has since
# deleted. Rebuilding at delivery time means what is sent reflects the record
# as it stands.
class CommentWebhookWorker
  include Sidekiq::Worker

  # Its own queue: an external endpoint can be arbitrarily slow, and it must
  # not sit in front of ingestion work.
  sidekiq_options queue: "webhooks", retry: 5

  TIMEOUT = 10

  sidekiq_retries_exhausted do |msg, exception|
    subscription_id = msg["args"][2]
    Rails.logger.error(
      "[CommentWebhookWorker] gave up delivering #{msg["args"][0]} to subscription #{subscription_id}: #{exception&.message}"
    )
    CommentWebhookSubscription.find_by(id: subscription_id)
                              &.record_failure!(error: "Retries exhausted: #{exception&.message}")
  end

  # @param event [String] one of {CommentWebhookSubscription::EVENTS}
  # @param record_id [String] Comment or CommentThread UUID, per the event
  # @param subscription_id [Integer]
  def perform(event, record_id, subscription_id)
    subscription = CommentWebhookSubscription.find_by(id: subscription_id)
    return if subscription.blank? || !subscription.active?

    payload = Comments::WebhookPayload.new(event: event, record_id: record_id).build
    # The record can legitimately vanish between enqueue and delivery — a
    # comment deleted seconds after posting. There is nothing to report.
    return if payload.blank?

    deliver(subscription, payload)
  end

  private

  def deliver(subscription, payload)
    body = payload.to_json

    response = Faraday.new { |f| f.options.timeout = TIMEOUT }.post(subscription.url) do |request|
      request.headers["Content-Type"]      = "application/json"
      request.headers["User-Agent"]        = "Capri-DAM-Webhook/1"
      request.headers["X-Capri-Event"]     = payload[:event]
      request.headers["X-Capri-Delivery"]  = SecureRandom.uuid
      # Signed over the exact bytes sent, so the receiver can verify both
      # origin and integrity. Computed after the body is serialised for
      # precisely that reason — re-serialising to verify would risk a
      # different key order and a mismatched signature.
      request.headers["X-Capri-Signature"] = subscription.signature_for(body)
      request.body = body
    end

    if response.success?
      subscription.record_success!(response.status)
    else
      subscription.record_failure!(status: response.status, error: response.body.to_s.truncate(500))
      # Raise so Sidekiq retries with backoff: a 5xx is usually transient.
      raise "Webhook #{subscription.url} responded #{response.status}"
    end
  rescue Faraday::Error => e
    subscription.record_failure!(error: e.message)
    raise
  end
end
