require "rails_helper"

RSpec.describe EmailOrchestrator do
  describe ".trigger" do
    let!(:template) { create(:email_template, event_trigger: "user_created", active: true) }

    it "returns false when no active template exists" do
      expect(described_class.trigger("missing", "user@example.com")).to be(false)
    end

    it "creates an audit delivery and queues the dispatcher" do
      allow(EmailDispatcherWorker).to receive(:perform_async)

      expect do
        described_class.trigger("user_created", "user@example.com", user: { first_name: "Jamie" })
      end.to change(EmailDelivery, :count).by(1)

      delivery = EmailDelivery.order(:created_at).last
      expect(delivery.payload).to eq("user" => { "first_name" => "Jamie" })
      expect(EmailDispatcherWorker).to have_received(:perform_async).with(delivery.id)
    end
  end
end
