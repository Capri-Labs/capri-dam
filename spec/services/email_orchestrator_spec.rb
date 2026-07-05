require "rails_helper"

RSpec.describe EmailOrchestrator do
  describe ".trigger" do
    let!(:template) { create(:email_template, event_trigger: "user_created", active: true) }

    it "returns false when no active template exists" do
      expect(described_class.trigger("missing", "user@example.com")).to be(false)
    end

    it "creates an audit delivery and queues the dispatcher, backfilling global template variables" do
      allow(EmailDispatcherWorker).to receive(:perform_async)

      expect do
        described_class.trigger("user_created", "user@example.com", user: { first_name: "Jamie" })
      end.to change(EmailDelivery, :count).by(1)

      delivery = EmailDelivery.order(:created_at).last
      expect(delivery.payload).to include("user" => { "first_name" => "Jamie" })
      expect(delivery.payload).to include("company", "app", "current_year", "current_date", "unsubscribe_url")
      expect(EmailDispatcherWorker).to have_received(:perform_async).with(delivery.id)
    end

    it "lets explicit payload values override the global defaults" do
      allow(EmailDispatcherWorker).to receive(:perform_async)

      described_class.trigger("user_created", "user@example.com", company: { name: "Custom Co" })

      delivery = EmailDelivery.order(:created_at).last
      expect(delivery.payload["company"]).to include("name" => "Custom Co")
    end
  end
end
