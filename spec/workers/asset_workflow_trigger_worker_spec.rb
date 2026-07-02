require "rails_helper"

RSpec.describe AssetWorkflowTriggerWorker, type: :worker do
  it "returns early when the asset is missing" do
    expect(WorkflowEvaluatorService).not_to receive(:call)

    described_class.new.perform(0, "on_upload")
  end

  it "delegates existing assets to the workflow evaluator" do
    asset = create(:asset)
    allow(WorkflowEvaluatorService).to receive(:call)

    described_class.new.perform(asset.id, "on_upload")

    expect(WorkflowEvaluatorService).to have_received(:call).with(asset, trigger_event: "on_upload")
  end
end
