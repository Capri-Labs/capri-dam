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
        # The advancer handles approval steps (generate tasks + wait) and
        # automated steps (run action + advance) uniformly.
        WorkflowAdvancerService.new(instance).process_step(first_step)
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
end
