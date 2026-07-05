require "rails_helper"

RSpec.describe WorkflowMailer, type: :mailer do
  describe ".task_assigned" do
    let(:user)     { create(:user) }
    let(:asset)    { create(:asset, user: user) }
    let(:workflow) { create(:workflow) }
    let(:instance) { create(:workflow_instance, asset: asset, workflow: workflow, status: "in_progress") }
    let(:task)     { create(:workflow_task, workflow_instance: instance, user: user) }

    it "emails the assignee" do
      mail = described_class.task_assigned(task.id)

      expect(mail.to).to eq([ user.email ])
      expect(mail.subject).to include(task.workflow_step.title)
      expect(mail.subject).to include("DAM Workflow Task Assigned")
    end

    it "builds an /assets?id=UUID link in the email body so recipients land directly on the asset (not the broken /dashboard?view=asset_explorer route)" do
      mail = described_class.task_assigned(task.id)

      expect(mail.body.encoded).to include("example.com/assets?id=#{asset.uuid}")
      expect(mail.body.encoded).not_to include("asset_explorer")
    end
  end
end
