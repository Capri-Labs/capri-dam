class AdminMailer < ApplicationMailer
  # Dynamic 'from' address resolving to your database configuration or falling back safely
  default from: -> {
    smtp_config = Setting.get("smtp_settings")
    smtp_config.is_a?(Hash) ? (smtp_config["sender_address"] || "noreply@yourdomain.com") : "noreply@yourdomain.com"
  }

  # Sends a highly informative, diagnostic test email to verify credentials and routing
  def test_connection_email(recipient)
    @timestamp = Time.current
    @environment = Rails.env
    @ruby_version = RUBY_VERSION
    @rails_version = Rails.version

    # Simple text/HTML body structure to verify rendering and layout integrity
    mail(
      to: recipient,
      subject: "🔔 Headless DAM Diagnostic Run: Outbound Mail Successful"
    ) do |format|
      format.text {
        render plain: <<~TEXT
          SMTP connection verified successfully!

          Diagnostic Details:
          -------------------
          Timestamp: #{@timestamp}
          Environment: #{@environment}
          Ruby Version: #{@ruby_version}
          Rails Version: #{@rails_version}

          Your Headless DAM outgoing system configuration is fully functional.
        TEXT
      }
    end
  end
end
