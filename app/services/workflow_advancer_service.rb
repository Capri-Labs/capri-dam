# frozen_string_literal: true

# Drives a {WorkflowInstance} forward one step at a time.
#
# A workflow blueprint is an ordered list of {WorkflowStep}s.  Steps are either:
#
#   * **approval**  — generates human {WorkflowTask}s and then *waits* for a
#     decision (handled by {WorkflowEngineWorker}); OR
#   * **automated** — runs a side effect via {WorkflowActionExecutor} and
#     immediately advances to the next step (no human interaction).
#
# This service centralises that logic so both {WorkflowInitiatorWorker} (first
# step) and {WorkflowEngineWorker} (subsequent steps) behave identically.
#
# It loops through consecutive automated steps in a single call so a chain like
# `Webhook → Set Status → Approval` stops only when it reaches the Approval step
# (or the end of the blueprint).
class WorkflowAdvancerService
  # Guards against an accidentally cyclic blueprint hanging the worker.
  MAX_AUTOMATED_CHAIN = 50

  def initialize(instance)
    @instance = instance
    @workflow = instance.workflow
  end

  # Processes +step+ and any following automated steps.
  #
  # @param step [WorkflowStep] the step to begin processing at
  # @return [void]
  def process_step(step)
    iterations = 0
    current    = step

    while current
      iterations += 1
      raise "Automated step chain exceeded #{MAX_AUTOMATED_CHAIN} — possible cycle" if iterations > MAX_AUTOMATED_CHAIN

      @instance.update!(current_step_id: current.id)

      if approval_step?(current)
        generate_tasks_for_step(@instance, current)
        return # wait for human decision
      end

      # Automated step: run the side effect, then continue to the next step.
      branch = WorkflowActionExecutor.new(@instance, current).call
      current = next_step_after(current, branch)
    end

    # No more steps — the workflow is complete.
    complete_instance!
  end

  private

  def approval_step?(step)
    # Treat nil node_type as approval for backward-compatibility with legacy rows.
    step.node_type.nil? || step.node_type == "approval"
  end

  def next_step_after(step, _branch = nil)
    # Linear advance by position. (Branch-aware routing via graph edges is a
    # future enhancement; conditions currently fall through to the next step.)
    @workflow.workflow_steps.find_by(position: step.position + 1)
  end

  def complete_instance!
    @instance.update!(status: "completed", completed_at: Time.current)
    @instance.asset.update!(status: "approved")
    Rails.logger.info("[WorkflowAdvancer] Instance #{@instance.id} completed")
  end

  # ── Human task generation (shared with the workers) ─────────────────────────

  def generate_tasks_for_step(instance, step)
    users = resolve_assignees(step)

    if users.empty?
      users = resolve_fallback(instance)
      Rails.logger.warn("[WorkflowAdvancer] Step '#{step.title}' fell back to workflow escalation") if users.any?
    end

    if users.empty?
      Rails.logger.error("[WorkflowAdvancer] FATAL: Step '#{step.title}' has no assignees or fallback")
      return
    end

    users.each do |user|
      task = WorkflowTask.create!(
        workflow_instance: instance,
        workflow_step:     step,
        user:              user,
        status:            "pending",
      )
      TaskNotificationWorker.perform_async(task.id)
    end
  end

  def resolve_assignees(step)
    case step.assignee_type
    when "user"
      [ User.find_by(id: step.assignee_id) ].compact
    when "group"
      group = UserGroup.find_by(id: step.assignee_id)
      group ? group.users.to_a : []
    else
      []
    end
  end

  def resolve_fallback(instance)
    workflow = instance.workflow
    case workflow.fallback_assignee_type
    when "user"
      [ User.find_by(id: workflow.fallback_assignee_id) ].compact
    when "group"
      group = UserGroup.find_by(id: workflow.fallback_assignee_id)
      group ? group.users.to_a : []
    else
      []
    end
  end
end
