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

  describe ".workflow_email" do
    it "sends an html+text alert with a normal priority header by default" do
      mail = described_class.workflow_email(to: "user@example.com", subject: "Workflow update", body: "<p>Hello <b>World</b></p>")

      expect(mail.to).to eq([ "user@example.com" ])
      expect(mail.subject).to eq("Workflow update")
      expect(mail["X-Priority"].to_s).to eq("3 (Normal)")
      expect(mail.text_part.body.encoded).to include("Hello World")
      expect(mail.html_part.body.encoded).to include("<b>World</b>")
    end

    it "sets the high priority header and includes cc recipients when provided" do
      mail = described_class.workflow_email(to: "user@example.com", cc: "manager@example.com", subject: "Urgent", body: "Act now", priority: "high")

      expect(mail.cc).to eq([ "manager@example.com" ])
      expect(mail["X-Priority"].to_s).to eq("1 (Highest)")
    end

    it "sets the low priority header" do
      mail = described_class.workflow_email(to: "user@example.com", subject: "FYI", body: "No rush", priority: "low")

      expect(mail["X-Priority"].to_s).to eq("5 (Lowest)")
    end
  end
end
