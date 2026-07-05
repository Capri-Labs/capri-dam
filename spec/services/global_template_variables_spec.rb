require "rails_helper"

RSpec.describe GlobalTemplateVariables do
  describe ".defaults" do
    it "falls back to sensible defaults when no SMTP settings are configured" do
      allow(Setting).to receive(:get).with("smtp_settings").and_return({})

      defaults = described_class.defaults

      expect(defaults["company"]).to include("name" => "Capri DAM", "support_email" => "support@capridam.com")
      expect(defaults["app"]).to include("name" => "Capri DAM")
      expect(defaults["current_year"]).to eq(Date.current.year.to_s)
      expect(defaults["current_date"]).to eq(Date.current.strftime("%B %d, %Y"))
      expect(defaults["unsubscribe_url"]).to end_with("/settings/notifications")
    end

    it "uses the configured SMTP sender name/address when present" do
      allow(Setting).to receive(:get).with("smtp_settings").and_return(
        { "sender_name" => "Acme DAM", "sender_address" => "hello@acme.test" }
      )

      defaults = described_class.defaults

      expect(defaults["company"]).to include("name" => "Acme DAM", "support_email" => "hello@acme.test")
    end
  end

  describe ".with_defaults" do
    it "backfills missing global keys without clobbering explicit payload values" do
      allow(Setting).to receive(:get).with("smtp_settings").and_return({})

      merged = described_class.with_defaults({ "company" => { "name" => "Custom Co" }, "user" => { "first_name" => "Ada" } })

      expect(merged["company"]).to include("name" => "Custom Co", "support_email" => "support@capridam.com")
      expect(merged["user"]).to eq("first_name" => "Ada")
      expect(merged["current_year"]).to eq(Date.current.year.to_s)
    end

    it "stringifies symbol keys from the caller's payload" do
      allow(Setting).to receive(:get).with("smtp_settings").and_return({})

      merged = described_class.with_defaults({ user: { first_name: "Ada" } })

      expect(merged["user"]).to eq("first_name" => "Ada")
    end
  end
end
