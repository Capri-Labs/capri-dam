class WorkflowEvaluatorService
  def self.call(asset, trigger_event: "on_upload")
    new(asset, trigger_event).evaluate_and_trigger!
  end

  def initialize(asset, trigger_event)
    @asset = asset
    @trigger_event = trigger_event
    @folder_id = asset.folder_id # Can be nil if it's in the root directory
  end

  def evaluate_and_trigger!
    # Fetch all active workflows that match this specific event
    eligible_workflows = Workflow.where(status: "active", trigger_type: @trigger_event)

    eligible_workflows.each do |workflow|
      if should_trigger?(workflow)
        Rails.logger.info "🎯 MATCH: Asset #{@asset.id} passed folder rules for Workflow '#{workflow.name}'"

        #  Hand off to the Initiator Worker, explicitly passing the exact Workflow ID
        WorkflowInitiatorWorker.perform_async(@asset.id, workflow.id)
      else
        Rails.logger.info "⏭️ SKIP: Asset #{@asset.id} excluded from Workflow '#{workflow.name}' by folder rules."
      end
    end
  end

  private

  def should_trigger?(workflow)
    # RULE 1: Specific Folders Only
    if workflow.folder_scope == "specific"
      # If the asset's folder isn't in the target list, skip it.
      return false unless workflow.target_folder_ids.include?(@folder_id)
    end

    # RULE 2: All Folders (with Exclusions)
    if workflow.folder_scope == "all"
      # If the asset's folder IS in the exclusion list, skip it.
      return false if workflow.exclude_folder_ids.include?(@folder_id)
    end

    # If it passed the above checks, it is authorized to run!
    true
  end
end
