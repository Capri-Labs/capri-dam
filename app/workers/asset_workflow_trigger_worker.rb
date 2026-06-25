class AssetWorkflowTriggerWorker
  include Sidekiq::Worker
  sidekiq_options queue: "workflow", retry: 3

  def perform(asset_id, trigger_event)
    asset = Asset.find_by(id: asset_id)
    return unless asset

    # Execute the Rules Engine!
    WorkflowEvaluatorService.call(asset, trigger_event: trigger_event)
  end
end
