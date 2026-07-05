require "rails_helper"

RSpec.describe SystemEmailConfig, type: :model do
  describe ".from_raw" do
    it "builds a typed config from the legacy loosely-typed settings hash" do
      config = described_class.from_raw(
        "enabled" => "true",
        "address" => "smtp.example.com",
        "port" => "2525",
        "domain" => "example.com",
        "user_name" => "mailer",
        "password" => "secret",
        "authentication" => "login",
        "enable_starttls_auto" => "true",
        "sender_address" => "ops@example.com",
        "sender_name" => "Capri DAM Ops"
      )

      expect(config.enabled).to be(true)
      expect(config.smtp_host).to eq("smtp.example.com")
      expect(config.smtp_port).to eq(2525)
      expect(config.security_protocol).to eq("starttls")
      expect(config.authentication).to eq("login")
      expect(config.default_from_address).to eq("ops@example.com")
      expect(config.default_from_name).to eq("Capri DAM Ops")
    end

    it "defaults to a disabled, non-TLS configuration for blank input" do
      config = described_class.from_raw(nil)

      expect(config.enabled).to be(false)
      expect(config.security_protocol).to eq("none")
      expect(config.smtp_port).to eq(587)
      expect(config.authentication).to eq("plain")
    end

    it "prefers an explicit security_protocol value over the legacy starttls flag" do
      config = described_class.from_raw("enable_starttls_auto" => "true", "security_protocol" => "ssl")

      expect(config.security_protocol).to eq("ssl")
    end
  end

  describe ".current" do
    it "loads the persisted smtp_settings row" do
      Setting.set("smtp_settings", "enabled" => "true", "address" => "smtp.example.com", "port" => "587")

      expect(described_class.current.smtp_host).to eq("smtp.example.com")
    end
  end

  describe "validations" do
    it "requires a host and port when enabled" do
      config = described_class.new(enabled: true, smtp_host: "", smtp_port: nil)

      expect(config).not_to be_valid
      expect(config.errors[:smtp_host]).to be_present
      expect(config.errors[:smtp_port]).to be_present
    end

    it "does not require a host/port when disabled" do
      config = described_class.new(enabled: false, smtp_host: nil, smtp_port: nil)

      expect(config).to be_valid
    end

    it "rejects an unknown security protocol" do
      config = described_class.new(security_protocol: "carrier_pigeon")

      expect(config).not_to be_valid
      expect(config.errors[:security_protocol]).to be_present
    end

    it "rejects a malformed default from address" do
      config = described_class.new(default_from_address: "not-an-email")

      expect(config).not_to be_valid
      expect(config.errors[:default_from_address]).to be_present
    end
  end

  describe "#persist!" do
    it "does not save invalid configuration" do
      config = described_class.new(enabled: true, smtp_host: "", smtp_port: nil)

      expect(config.persist!).to be(false)
      expect(Setting.get("smtp_settings")).to be_nil
    end

    it "saves valid configuration and re-applies it to ActionMailer" do
      config = described_class.new(enabled: true, smtp_host: "smtp.example.com", smtp_port: 587, smtp_username: "mailer", smtp_password: "secret")

      expect(config.persist!).to be(true)
      expect(Setting.get("smtp_settings")).to include("address" => "smtp.example.com")
    end
  end

  describe "#net_smtp_options" do
    it "maps security_protocol to the correct Net::SMTP flags" do
      starttls = described_class.new(security_protocol: "starttls")
      ssl = described_class.new(security_protocol: "ssl")
      none = described_class.new(security_protocol: "none")

      expect(starttls.net_smtp_options).to include(enable_starttls_auto: true, ssl: false)
      expect(ssl.net_smtp_options).to include(enable_starttls_auto: false, ssl: true)
      expect(none.net_smtp_options).to include(enable_starttls_auto: false, ssl: false)
    end
  end

  describe "#from_address_with_name" do
    it "combines the name and address when both are present" do
      config = described_class.new(default_from_address: "ops@example.com", default_from_name: "Capri DAM Ops")

      expect(config.from_address_with_name).to eq("Capri DAM Ops <ops@example.com>")
    end

    it "falls back to the bare address when no name is configured" do
      config = described_class.new(default_from_address: "ops@example.com")

      expect(config.from_address_with_name).to eq("ops@example.com")
    end

    it "falls back to the environment default when nothing is configured" do
      config = described_class.new

      expect(config.from_address_with_name).to eq(ENV.fetch("MAILER_SENDER_ADDRESS", "noreply@yourdam.com"))
    end
  end
end
