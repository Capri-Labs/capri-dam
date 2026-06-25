class WorkflowInitiatorWorker
  include Sidekiq::Worker
  sidekiq_options queue: "workflow", retry: 3

  #  CHANGED: Now accepts workflow_id instead of trigger_event
  def perform(asset_id, workflow_id)
    Rails.logger.info "🕵️ WorkflowInitiator started | Asset: #{asset_id} | Blueprint: #{workflow_id}"

    asset = Asset.find_by(id: asset_id)
    if asset.nil?
      Rails.logger.warn "⚠️ ABORT: Could not find Asset with ID #{asset_id}."
      return
    end

    #  Fetch the exact blueprint passed by the Evaluator Service
    workflow = Workflow.find_by(id: workflow_id, status: "active")
    if workflow.nil?
      Rails.logger.warn "⚠️ ABORT: Blueprint #{workflow_id} is missing or inactive."
      return
    end

    ActiveRecord::Base.transaction do
      # 1. Lock the asset into review mode
      asset.update!(status: "in_review")

      # 2. Create the immutable Workflow Instance
      instance = WorkflowInstance.create!(
        asset: asset,
        workflow: workflow,
        status: "in_progress",
        started_at: Time.current,
        blueprint_snapshot: generate_snapshot(workflow)
      )

      # 3. Generate Tasks for Step 1
      first_step = workflow.workflow_steps.order(:position).first

      if first_step
        instance.update!(current_step_id: first_step.id)
        generate_tasks_for_step(instance, first_step)
        Rails.logger.info " Workflow #{workflow.name} initiated successfully for Asset #{asset.id}"
      else
        # Safety Valve: Workflow has no steps
        instance.update!(status: "completed", completed_at: Time.current)
        asset.update!(status: "approved")
        Rails.logger.warn "⚠️ Workflow #{workflow.name} had zero steps. Auto-approved."
      end
    end
  rescue StandardError => e
    Rails.logger.error "💥 Workflow Initiation Failed for Asset #{asset_id}: #{e.message}"
    raise e
  end

  private

  def generate_snapshot(workflow)
    workflow.as_json(include: :workflow_steps)
  end

  def generate_tasks_for_step(instance, step)
    users = resolve_assignees(step) || []

    if users.empty?
      Rails.logger.warn "⚠️ No primary assignees found. Attempting fallback..."
      workflow = instance.workflow

      if workflow.fallback_assignee_type == "user"
        users << User.find_by(id: workflow.fallback_assignee_id)
      elsif workflow.fallback_assignee_type == "group"
        group = UserGroup.find_by(id: workflow.fallback_assignee_id)
        users = group.users if group
      end

      users = users.flatten.compact
    end

    if users.empty?
      Rails.logger.error "💥 FATAL: Step '#{step.title}' has no assignees and no fallback! Skipping task creation."
      return
    end

    users.each do |user|
      task = WorkflowTask.create!(
        workflow_instance: instance,
        workflow_step: step,
        user: user,
        status: "pending"
      )

      TaskNotificationWorker.perform_async(task.id)
    end
  end

  def resolve_assignees(step)
    if step.assignee_type == "user"
      [ User.find_by(id: step.assignee_id) ].compact
    elsif step.assignee_type == "group"
      group = UserGroup.find_by(id: step.assignee_id)
      group ? group.users : []
    else
      []
    end
  end
end
