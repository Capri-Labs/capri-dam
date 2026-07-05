class AdminMailer < ApplicationMailer
  # Dynamic 'from' address resolving to your database configuration or falling back safely
  default from: -> { SystemEmailConfig.current.from_address_with_name }

  # Sends a highly informative, diagnostic test email to verify credentials and routing
  def test_connection_email(recipient)
    @timestamp = Time.current
    @environment = Rails.env
    @ruby_version = RUBY_VERSION
    @rails_version = Rails.version

    # Simple text/HTML body structure to verify rendering and layout integrity
    mail(
      to: recipient,
      subject: "🔔 Capri DAM Diagnostic Run: Outbound Mail Successful"
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

          Your Capri DAM outgoing system configuration is fully functional.
        TEXT
      }
    end
  end
end
