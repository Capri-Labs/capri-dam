require "rails_helper"

RSpec.describe WorkflowEngineWorker, type: :worker do
  let(:user) { create(:user) }
  let(:asset) { create(:asset, user: user, status: :in_review) }
  let(:workflow) { create(:workflow, status: :draft) }
  let(:step) { create(:workflow_step, workflow: workflow, position: 1, logic: "any") }
  let(:instance) { create(:workflow_instance, asset: asset, workflow: workflow, status: "in_progress") }

  before do
    step
    workflow.update!(status: :active)
  end

  it "returns early when the task is missing" do
    expect { described_class.new.perform(0) }.not_to raise_error
  end

  it "rejects the workflow and cancels pending sibling tasks" do
    task = create(:workflow_task, workflow_instance: instance, workflow_step: step, user: user, status: "rejected")
    sibling = create(:workflow_task, workflow_instance: instance, workflow_step: step, user: user, status: "pending")

    described_class.new.perform(task.id)

    expect(instance.reload.status).to eq("rejected")
    expect(asset.reload.read_attribute_before_type_cast("status")).to eq(Asset.statuses["rejected"].to_s)
    expect(sibling.reload.status).to eq("canceled")
  end

  it "completes the workflow when the last step is approved" do
    task = create(:workflow_task, workflow_instance: instance, workflow_step: step, user: user, status: "approved")

    described_class.new.perform(task.id)

    expect(instance.reload.status).to eq("completed")
    expect(asset.reload.read_attribute_before_type_cast("status")).to eq(Asset.statuses["approved"].to_s)
  end

  it "advances to the next step when one exists" do
    task = create(:workflow_task, workflow_instance: instance, workflow_step: step, user: user, status: "approved")
    next_step = create(:workflow_step, workflow: workflow, position: 2)
    service = instance_double(WorkflowAdvancerService, process_step: true)
    allow(WorkflowAdvancerService).to receive(:new).with(instance).and_return(service)

    described_class.new.perform(task.id)

    expect(service).to have_received(:process_step).with(next_step)
    expect(instance.reload.status).to eq("in_progress")
  end

  it "waits for more approvals when all logic still has pending tasks" do
    step.update!(logic: "all")
    task = create(:workflow_task, workflow_instance: instance, workflow_step: step, user: user, status: "approved")
    create(:workflow_task, workflow_instance: instance, workflow_step: step, user: create(:user), status: "pending")

    described_class.new.perform(task.id)

    expect(instance.reload.status).to eq("in_progress")
  end
end
