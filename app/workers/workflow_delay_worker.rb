# frozen_string_literal: true

# WorkflowDelayWorker – resumes a paused workflow after a configured delay.
#
# Enqueued by WorkflowActionExecutor#handle_delay via Sidekiq's
# `perform_in(seconds, …)` scheduled job API.  When it fires it picks up
# the instance where it left off and calls WorkflowAdvancerService to
# advance to the step immediately following the delay step.
class WorkflowDelayWorker
  include Sidekiq::Worker
  sidekiq_options queue: "workflow", retry: 3

  def perform(instance_id, delay_step_id)
    instance   = WorkflowInstance.find_by(id: instance_id)
    delay_step = WorkflowStep.find_by(id: delay_step_id)

    unless instance && delay_step
      Rails.logger.warn("[WorkflowDelayWorker] Skipping — instance #{instance_id} or step #{delay_step_id} not found")
      return
    end

    # If the workflow was cancelled while we were sleeping, do nothing.
    if instance.terminal?
      Rails.logger.info("[WorkflowDelayWorker] Instance #{instance_id} is terminal — nothing to resume")
      return
    end

    next_step = instance.workflow.workflow_steps.find_by(position: delay_step.position + 1)
    if next_step
      WorkflowAdvancerService.new(instance).process_step(next_step)
      Rails.logger.info("[WorkflowDelayWorker] Resumed instance #{instance_id} at step #{next_step.position}")
    else
      instance.update!(status: "completed", completed_at: Time.current)
      instance.asset.update!(status: "approved")
      Rails.logger.info("[WorkflowDelayWorker] Instance #{instance_id} completed after delay (last step)")
    end
  rescue StandardError => e
    Rails.logger.error("[WorkflowDelayWorker] Failed for instance #{instance_id}: #{e.message}")
    raise
  end
end
