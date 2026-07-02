require "rails_helper"

RSpec.describe TaskNotificationWorker, type: :worker do
  let(:user) { create(:user) }
  let(:asset) { create(:asset, title: "Review Me") }
  let(:workflow) { create(:workflow) }
  let(:step) { create(:workflow_step, workflow: workflow, title: "Legal Review") }
  let(:instance) { create(:workflow_instance, asset: asset, workflow: workflow) }
  let(:mail_message) { instance_double(ActionMailer::MessageDelivery, deliver_later: true) }

  it "returns early for missing or non-pending tasks" do
    approved = create(:workflow_task, workflow_instance: instance, workflow_step: step, user: user, status: "approved")

    expect { described_class.new.perform(0) }.not_to change(Notification, :count)
    expect { described_class.new.perform(approved.id) }.not_to change(Notification, :count)
  end

  it "creates an in-app notification and enqueues the assignment email" do
    task = create(:workflow_task, workflow_instance: instance, workflow_step: step, user: user, status: "pending")
    allow(WorkflowMailer).to receive(:task_assigned).with(task.id).and_return(mail_message)

    expect { described_class.new.perform(task.id) }.to change(Notification, :count).by(1)

    notification = Notification.last
    expect(notification.user).to eq(user)
    expect(notification.title).to include("Legal Review")
    expect(notification.message).to include("Review Me")
    expect(mail_message).to have_received(:deliver_later)
  end

  it "logs and reraises notification failures" do
    task = create(:workflow_task, workflow_instance: instance, workflow_step: step, user: user, status: "pending")
    allow(Notification).to receive(:create!).and_raise(StandardError, "notify failed")

    expect { described_class.new.perform(task.id) }.to raise_error(StandardError, "notify failed")
  end
end
