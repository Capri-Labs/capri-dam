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
      # A :delay_scheduled return means a WorkflowDelayWorker has been queued
      # and will resume the chain — stop advancing here.
      branch = WorkflowActionExecutor.new(@instance, current).call
      return if branch == :delay_scheduled

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

  def next_step_after(step, branch = nil)
    # Branching nodes return a source-handle id to follow. The graph edges are
    # stored in the workflow's graph_data JSON:
    #   edges: [{ source: "nodeId", sourceHandle: "<handle>", target: "nodeId" }]
    #
    #   * condition → :true_branch / :false_branch  → handle "true" / "false"
    #   * switch / branching plugin → [:branch, "<handle>"] → that handle id
    #
    # We follow the matching edge; if graph_data is absent we fall back to linear
    # position advance (safe for simple non-branching workflows).
    handle = branch_handle(branch)
    if handle
      graph = @workflow.graph_data || {}
      edges = Array(graph["edges"] || graph[:edges])
      edge  = edges.find { |e|
        (e["source"] == step.id.to_s || e[:source] == step.id.to_s) &&
        (e["sourceHandle"].to_s == handle || e[:sourceHandle].to_s == handle)
      }
      if edge
        target_id = (edge["target"] || edge[:target]).to_s
        # Find the workflow_step whose canvas node id matches.  The canvas node
        # id is stored in step.node_id (populated by the designer on save) or
        # we fall back to position-based lookup.
        next_s = @workflow.workflow_steps.find_by(node_id: target_id) if WorkflowStep.column_names.include?("node_id")
        next_s ||= @workflow.workflow_steps.find_by(position: step.position + 1)
        return next_s
      end
    end

    # Linear advance by position
    @workflow.workflow_steps.find_by(position: step.position + 1)
  end

  # Maps a branching-node result to the canvas source-handle id to follow.
  def branch_handle(branch)
    case branch
    when :true_branch  then "true"
    when :false_branch then "false"
    when Array         then (branch.first == :branch ? branch.last.to_s : nil)
    end
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
      # Step-level fallback (configured on the step's ApprovalNode in the
      # Visual Designer — takes precedence over the legacy workflow-level field).
      users = resolve_step_fallback(step)
      if users.any?
        Rails.logger.info("[WorkflowAdvancer] Step '#{step.title}' using step-level fallback assignee")
      end
    end

    if users.empty?
      # Legacy workflow-level fallback (kept for backward-compat with workflows
      # saved before the step-level fallback columns were added).
      users = resolve_workflow_fallback(instance)
      Rails.logger.warn("[WorkflowAdvancer] Step '#{step.title}' fell back to workflow-level escalation") if users.any?
    end

    if users.empty?
      Rails.logger.error("[WorkflowAdvancer] FATAL: Step '#{step.title}' has no assignees or any fallback")
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

  # Step-level escalation — configured per ApprovalNode in the designer.
  def resolve_step_fallback(step)
    return [] unless step.respond_to?(:has_step_fallback?) && step.has_step_fallback?

    case step.fallback_assignee_type
    when "user"
      [ User.find_by(id: step.fallback_assignee_id) ].compact
    when "group"
      group = UserGroup.find_by(id: step.fallback_assignee_id)
      group ? group.users.to_a : []
    else
      []
    end
  end

  # Legacy workflow-level escalation — still honoured for backward-compat.
  def resolve_workflow_fallback(instance)
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
