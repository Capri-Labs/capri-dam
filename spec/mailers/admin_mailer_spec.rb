require "rails_helper"

RSpec.describe AdminMailer, type: :mailer do
  describe ".test_connection_email" do
    it "renders the recipient, subject, sender, and body" do
      allow(Setting).to receive(:get).with("smtp_settings").and_return({ "sender_address" => "ops@example.com" })

      mail = described_class.test_connection_email("user@example.com")

      expect(mail.to).to eq([ "user@example.com" ])
      expect(mail.from).to eq([ "ops@example.com" ])
      expect(mail.subject).to eq("🔔 Capri DAM Diagnostic Run: Outbound Mail Successful")
      expect(mail.body.encoded).to include("SMTP connection verified successfully!")
      expect(mail.body.encoded).to include(Rails.env)
      expect(mail.body.encoded).to include(Rails.version)
    end

    it "falls back to the default sender when smtp settings are not a hash" do
      allow(Setting).to receive(:get).with("smtp_settings").and_return("disabled")

      mail = described_class.test_connection_email("user@example.com")

      expect(mail.from).to eq([ "noreply@yourdomain.com" ])
    end
  end
end
