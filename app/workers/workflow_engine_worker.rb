class WorkflowEngineWorker
  include Sidekiq::Worker
  sidekiq_options queue: "workflow", retry: 3

  def perform(task_id)
    task = WorkflowTask.find_by(id: task_id)
    return unless task

    instance = task.workflow_instance
    step = task.workflow_step
    asset = instance.asset

    ActiveRecord::Base.transaction do
      # -------------------------------------------------------------
      # SCENARIO A: The user REJECTED the asset.
      # -------------------------------------------------------------
      if task.status == "rejected"
        #  Changed 'failed' to 'rejected' so the Dashboard API picks it up
        instance.update!(status: "rejected", completed_at: Time.current)

        # Update the asset status
        asset.update!(status: "rejected")

        # Cancel any sibling tasks for this step that haven't been answered yet
        cancel_pending_tasks(instance)

        Rails.logger.info "❌ Workflow #{instance.id} rejected by User #{task.user_id}"
        return # Exit the worker completely
      end

      # -------------------------------------------------------------
      # SCENARIO B: The user APPROVED the asset.
      # -------------------------------------------------------------
      if task.status == "approved"
        # Evaluate if the overall Step is now complete based on its logic
        if step_complete?(step, instance)

          # Clean up remaining tasks (e.g., if logic was 'Any', cancel the others)
          cancel_pending_tasks(instance)

          # Find the next step in the blueprint snapshot
          next_step = instance.workflow.workflow_steps.find_by(position: step.position + 1)

          if next_step
            # MOVE FORWARD: the advancer handles approval (tasks) + automated
            # (run action and continue) steps uniformly.
            WorkflowAdvancerService.new(instance).process_step(next_step)
            Rails.logger.info "⏭️ Workflow #{instance.id} advanced to Step #{next_step.position}"
          else
            # VICTORY: No more steps! The workflow is successfully finished.
            instance.update!(status: "completed", completed_at: Time.current)
            asset.update!(status: "approved")
            Rails.logger.info "✅ Workflow #{instance.id} fully completed!"
          end
        else
          # The user approved, but the step requires 'All' and we are still waiting on others.
          Rails.logger.info "⏳ Workflow #{instance.id} waiting on additional approvals for Step #{step.position}"
        end
      end
    end
  rescue StandardError => e
    Rails.logger.error "💥 Engine failed for Task #{task_id}: #{e.message}"
    raise e
  end

  private

  # Evaluates whether the step criteria has been met
  def step_complete?(step, instance)
    if step.logic == "any"
      # One approval is all we need!
      return true
    elsif step.logic == "all"
      # It's complete ONLY if there are zero pending tasks left for this step
      pending_count = instance.workflow_tasks.where(workflow_step: step, status: "pending").count
      return pending_count.zero?
    end

    # Fallback to true to prevent infinite hanging if logic string was corrupted
    true
  end

  # Cancels all remaining pending tasks for the current instance
  def cancel_pending_tasks(instance)
    instance.workflow_tasks.where(status: "pending").update_all(
      status: "canceled",
      completed_at: Time.current
    )
  end
end
