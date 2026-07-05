require "rails_helper"

RSpec.describe CentralNotificationMailer do
  describe "#build_template_mail" do
    it "applies the database SMTP configuration and builds the DynamicMailer message" do
      message = instance_double(ActionMailer::MessageDelivery)
      allow(Setting).to receive(:apply_smtp_settings!)
      allow(DynamicMailer).to receive(:dispatch_email).and_return(message)

      result = described_class.build_template_mail(to: "user@example.com", subject: "Hi", html_body: "<p>hi</p>", text_body: "hi")

      expect(Setting).to have_received(:apply_smtp_settings!)
      expect(DynamicMailer).to have_received(:dispatch_email).with(to: "user@example.com", subject: "Hi", html_body: "<p>hi</p>", text_body: "hi")
      expect(result).to eq(message)
    end
  end

  describe "#build_admin_test_mail" do
    it "applies the configuration and delegates to AdminMailer" do
      message = instance_double(ActionMailer::MessageDelivery)
      allow(Setting).to receive(:apply_smtp_settings!)
      allow(AdminMailer).to receive(:test_connection_email).and_return(message)

      result = described_class.build_admin_test_mail("ops@example.com")

      expect(Setting).to have_received(:apply_smtp_settings!)
      expect(AdminMailer).to have_received(:test_connection_email).with("ops@example.com")
      expect(result).to eq(message)
    end
  end

  describe "#deliver_workflow_task_assigned" do
    it "applies the configuration and queues the task-assigned mail" do
      message = instance_double(ActionMailer::MessageDelivery, deliver_later: true)
      allow(Setting).to receive(:apply_smtp_settings!)
      allow(WorkflowMailer).to receive(:task_assigned).and_return(message)

      described_class.deliver_workflow_task_assigned(42)

      expect(Setting).to have_received(:apply_smtp_settings!)
      expect(WorkflowMailer).to have_received(:task_assigned).with(42)
      expect(message).to have_received(:deliver_later)
    end
  end

  describe "#deliver_workflow_alert" do
    it "applies the configuration and queues the workflow alert mail" do
      message = instance_double(ActionMailer::MessageDelivery, deliver_later: true)
      allow(Setting).to receive(:apply_smtp_settings!)
      allow(WorkflowMailer).to receive(:workflow_email).and_return(message)

      described_class.deliver_workflow_alert(to: "user@example.com", subject: "Subj", body: "Body", priority: "high")

      expect(Setting).to have_received(:apply_smtp_settings!)
      expect(WorkflowMailer).to have_received(:workflow_email).with(to: "user@example.com", cc: nil, subject: "Subj", body: "Body", priority: "high")
      expect(message).to have_received(:deliver_later)
    end
  end
end
