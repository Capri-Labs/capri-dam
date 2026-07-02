require "rails_helper"

RSpec.describe WorkflowInitiatorWorker, type: :worker do
  let(:asset) { create(:asset, status: :ready) }
  let(:workflow) { create(:workflow, status: :draft) }

  it "returns early when the asset is missing or workflow inactive" do
    draft = create(:workflow, status: :draft)
    workflow.update_column(:status, Workflow.statuses[:active])

    expect { described_class.new.perform(0, workflow.id) }.not_to change(WorkflowInstance, :count)
    expect { described_class.new.perform(asset.id, draft.id) }.not_to change(WorkflowInstance, :count)
  end

  it "creates an instance, snapshots the blueprint and delegates the first step" do
    step = create(:workflow_step, workflow: workflow, position: 1)
    workflow.update!(status: :active)
    service = instance_double(WorkflowAdvancerService, process_step: true)
    allow(WorkflowAdvancerService).to receive(:new).and_return(service)

    expect { described_class.new.perform(asset.id, workflow.id) }.to change(WorkflowInstance, :count).by(1)

    instance = WorkflowInstance.last
    expect(asset.reload.read_attribute_before_type_cast("status")).to eq(Asset.statuses["in_review"].to_s)
    expect(instance.blueprint_snapshot).to include("workflow_steps")
    expect(service).to have_received(:process_step).with(step)
  end

  it "auto-approves workflows with no steps" do
    workflow.update_column(:status, Workflow.statuses[:active])

    described_class.new.perform(asset.id, workflow.id)

    expect(WorkflowInstance.last.status).to eq("completed")
    expect(asset.reload.read_attribute_before_type_cast("status")).to eq(Asset.statuses["approved"].to_s)
  end
end
