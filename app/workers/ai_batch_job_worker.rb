# frozen_string_literal: true

# Dispatches an {AiBatchJob} to the AI Gateway.
#
# Responsibilities (kept deliberately thin — all inference happens in the
# gateway):
#   1. Resolve the configured target dataset via {Ai::BatchTaskRegistry}.
#   2. Record the total number of targets on the job.
#   3. Mark the job +running+.
#   4. Broadcast a single `ai_batch.dispatch` event to the gateway over Redis.
#
# The gateway then processes the targets and streams progress back via
# POST /api/v1/ai_batch_jobs/:id/progress (gateway-secret authenticated).
#
# Idempotency: the worker no-ops unless the job is still +queued+, so Sidekiq
# retries never double-dispatch a job that already started.
#
# @see AiBatchJob
# @see Api::V1::AiBatchJobsController
class AiBatchJobWorker
  include Sidekiq::Worker

  sidekiq_options queue: "smartai", retry: 3

  # Hard cap on identifiers embedded in a single gateway message to keep the
  # Redis payload bounded; the gateway paginates beyond this via its own cursor.
  MAX_BROADCAST_IDS = 5_000

  def perform(job_id)
    job = AiBatchJob.find_by(id: job_id)
    return unless job&.status == "queued"

    targets = Ai::BatchTaskRegistry.resolve_targets(job.target_scope)
    total   = targets.count

    job.update!(status: "running", total_count: total, started_at: Time.current)

    if total.zero?
      job.update!(status: "completed", completed_at: Time.current)
      return
    end

    target_ids = targets.limit(MAX_BROADCAST_IDS).pluck(:id).map(&:to_s)
    broadcast_to_gateway(job, target_ids)
  rescue StandardError => e
    job&.update(status: "failed", error_message: e.message, completed_at: Time.current)
    raise
  end

  private

  def broadcast_to_gateway(job, target_ids)
    payload = job.to_gateway_payload(target_ids).to_json
    Sidekiq.redis { |conn| conn.publish("ai_gateway_events", payload) }
  rescue StandardError => e
    Rails.logger.warn("[AiBatchJob##{job.id}] gateway dispatch skipped: #{e.message}")
  end
end
