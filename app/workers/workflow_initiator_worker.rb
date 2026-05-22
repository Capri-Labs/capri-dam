class WorkflowInitiatorWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'workflow', retry: 3

  def perform(asset_id, trigger_event)

    Rails.logger.info "🕵️ WorkflowInitiator started | Asset ID passed: #{asset_id} | Trigger: #{trigger_event}"

    asset = Asset.find_by(id: asset_id)
    if asset.nil?
      Rails.logger.warn "⚠️ ABORT: Could not find Asset with ID #{asset_id}. Did you pass a UUID instead?"
      return
    end

    workflow = Workflow.find_by(status: 'active', trigger_type: trigger_event)
    if workflow.nil?
      Rails.logger.warn "⚠️ ABORT: No active workflow blueprint found for trigger '#{trigger_event}'"
      return
    end

    # We wrap this in a transaction. If task generation fails halfway through,
    # it rolls back the entire instance creation so we don't get corrupted states.
    ActiveRecord::Base.transaction do
      # 2. Lock the asset into review mode
      asset.update!(status: 'in_review')

      # 3. Create the immutable Workflow Instance
      instance = WorkflowInstance.create!(
        asset: asset,
        workflow: workflow,
        status: 'in_progress',
        started_at: Time.current,
        # Snapshot the entire blueprint into JSON so future admin edits don't break this run
        blueprint_snapshot: generate_snapshot(workflow)
      )

      # 4. Generate Tasks for Step 1
      first_step = workflow.workflow_steps.order(:position).first

      if first_step
        instance.update!(current_step_id: first_step.id)
        generate_tasks_for_step(instance, first_step)
        Rails.logger.info "🚀 Workflow #{workflow.name} initiated for Asset #{asset.id}"
      else
        # Edge case safety: The admin created a workflow but added zero steps to it.
        # Mark as instantly completed to prevent the asset from being stuck forever.
        instance.update!(status: 'completed', completed_at: Time.current)
        asset.update!(status: 'approved')
      end
    end
  rescue StandardError => e
    Rails.logger.error "💥 Workflow Initiation Failed for Asset #{asset_id}: #{e.message}"
    raise e # Re-raise to trigger Sidekiq retries
  end

  private

  # Dumps the workflow and its nested steps into a JSON object
  def generate_snapshot(workflow)
    workflow.as_json(include: :workflow_steps)
  end

  # Figures out who gets the task and creates the database records
  def generate_tasks_for_step(instance, step)
    users = resolve_assignees(step) || []

    if users.empty?
      Rails.logger.warn "⚠️ No primary assignees found. Attempting fallback..."
      workflow = instance.workflow

      if workflow.fallback_assignee_type == 'user'
        users << User.find_by(id: workflow.fallback_assignee_id)
      elsif workflow.fallback_assignee_type == 'group'
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
        status: 'pending'
      )

      TaskNotificationWorker.perform_async(task.id)
    end
  end

  # Let's also double-check this method! Make sure yours looks like this:
  def resolve_assignees(step)
    if step.assignee_type == 'user'
      [User.find_by(id: step.assignee_id)].compact
    elsif step.assignee_type == 'group'
      group = UserGroup.find_by(id: step.assignee_id)
      group ? group.users : []
    else
      []
    end
  end

end