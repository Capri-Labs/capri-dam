require "rails_helper"

RSpec.describe SmtpConnectionValidator do
  describe "#call" do
    it "returns INVALID_CONFIGURATION without attempting a handshake when the config is invalid" do
      config = SystemEmailConfig.new(enabled: true, smtp_host: "", smtp_port: nil)

      expect(Net::SMTP).not_to receive(:new)

      result = described_class.new(config).call

      expect(result.success?).to be(false)
      expect(result.error_code).to eq("INVALID_CONFIGURATION")
    end

    it "returns success when the handshake completes without error" do
      config = SystemEmailConfig.new(enabled: true, smtp_host: "smtp.example.com", smtp_port: 587)
      smtp = instance_double(Net::SMTP, enable_starttls_auto: nil, "open_timeout=": nil, "read_timeout=": nil)
      allow(Net::SMTP).to receive(:new).and_return(smtp)
      allow(smtp).to receive(:start).and_yield

      result = described_class.new(config).call

      expect(result.success?).to be(true)
      expect(result.error_code).to be_nil
    end

    {
      Net::SMTPAuthenticationError => "SMTP_AUTHENTICATION_FAILED",
      Net::SMTPServerBusy => "SMTP_SERVER_BUSY",
      Net::OpenTimeout => "CONNECTION_TIMEOUT",
      Errno::ECONNREFUSED => "CONNECTION_REFUSED",
      SocketError => "HOST_UNREACHABLE",
    }.each do |error_class, expected_code|
      it "maps #{error_class} to #{expected_code}" do
        config = SystemEmailConfig.new(enabled: true, smtp_host: "smtp.example.com", smtp_port: 587)
        smtp = instance_double(Net::SMTP, enable_starttls_auto: nil, "open_timeout=": nil, "read_timeout=": nil)
        allow(Net::SMTP).to receive(:new).and_return(smtp)
        allow(smtp).to receive(:start).and_raise(error_class, "boom")

        result = described_class.new(config).call

        expect(result.success?).to be(false)
        expect(result.error_code).to eq(expected_code)
      end
    end

    it "maps OpenSSL::SSL::SSLError to SSL_CERTIFICATE_ERROR" do
      config = SystemEmailConfig.new(enabled: true, smtp_host: "smtp.example.com", smtp_port: 465, security_protocol: "ssl")
      smtp = instance_double(Net::SMTP, enable_tls: nil, "open_timeout=": nil, "read_timeout=": nil)
      allow(Net::SMTP).to receive(:new).and_return(smtp)
      allow(smtp).to receive(:start).and_raise(OpenSSL::SSL::SSLError, "cert invalid")

      result = described_class.new(config).call

      expect(result.success?).to be(false)
      expect(result.error_code).to eq("SSL_CERTIFICATE_ERROR")
    end

    it "maps unexpected errors to SMTP_ERROR" do
      config = SystemEmailConfig.new(enabled: true, smtp_host: "smtp.example.com", smtp_port: 587)
      smtp = instance_double(Net::SMTP, enable_starttls_auto: nil, "open_timeout=": nil, "read_timeout=": nil)
      allow(Net::SMTP).to receive(:new).and_return(smtp)
      allow(smtp).to receive(:start).and_raise(StandardError, "mystery failure")

      result = described_class.new(config).call

      expect(result.success?).to be(false)
      expect(result.error_code).to eq("SMTP_ERROR")
    end
  end
end
