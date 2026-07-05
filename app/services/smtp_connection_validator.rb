require "net/smtp"

# Performs a strict, non-blocking pre-flight connection handshake against an
# SMTP server described by a SystemEmailConfig, without sending any mail.
# Used by Admin::SystemStatusController on both "Save" and "Test Connection"
# so invalid credentials can never be persisted as the active configuration.
class SmtpConnectionValidator
  ERROR_CODES = {
    invalid_config: "INVALID_CONFIGURATION",
    timeout: "CONNECTION_TIMEOUT",
    refused: "CONNECTION_REFUSED",
    unreachable: "HOST_UNREACHABLE",
    auth_failed: "SMTP_AUTHENTICATION_FAILED",
    ssl_error: "SSL_CERTIFICATE_ERROR",
    server_busy: "SMTP_SERVER_BUSY",
    unknown: "SMTP_ERROR",
  }.freeze

  Result = Struct.new(:success, :error_code, :message, keyword_init: true) do
    def success?
      !!success
    end

    def as_json(*)
      { success: success, error_code: error_code, message: message }.compact
    end
  end

  DEFAULT_OPEN_TIMEOUT = 5
  DEFAULT_READ_TIMEOUT = 5

  def initialize(config, open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT)
    @config = config.is_a?(SystemEmailConfig) ? config : SystemEmailConfig.from_raw(config)
    @open_timeout = open_timeout
    @read_timeout = read_timeout
  end

  def call
    return invalid_config_result unless @config.valid?

    perform_handshake
  end

  private

  def invalid_config_result
    Result.new(success: false, error_code: ERROR_CODES[:invalid_config], message: @config.errors.full_messages.to_sentence)
  end

  def perform_handshake
    opts = @config.net_smtp_options
    smtp = Net::SMTP.new(opts[:address], opts[:port])
    smtp.enable_starttls_auto if opts[:enable_starttls_auto]
    smtp.enable_tls if opts[:ssl]
    smtp.open_timeout = @open_timeout
    smtp.read_timeout = @read_timeout

    # `start` performs the full handshake (connect + EHLO/HELO + AUTH) and
    # `finish` (implicit via the block form) cleanly tears the socket down
    # without transmitting a MAIL FROM/DATA command, i.e. no email is sent.
    smtp.start(opts[:domain], opts[:user_name], opts[:password], opts[:authentication]) { }

    Result.new(success: true)
  rescue Net::SMTPAuthenticationError => e
    Result.new(success: false, error_code: ERROR_CODES[:auth_failed], message: e.message)
  rescue Net::SMTPServerBusy => e
    Result.new(success: false, error_code: ERROR_CODES[:server_busy], message: e.message)
  rescue OpenSSL::SSL::SSLError => e
    Result.new(success: false, error_code: ERROR_CODES[:ssl_error], message: e.message)
  rescue Net::OpenTimeout, Timeout::Error => e
    Result.new(success: false, error_code: ERROR_CODES[:timeout], message: e.message)
  rescue Errno::ECONNREFUSED => e
    Result.new(success: false, error_code: ERROR_CODES[:refused], message: e.message)
  rescue SocketError, Errno::EHOSTUNREACH => e
    Result.new(success: false, error_code: ERROR_CODES[:unreachable], message: e.message)
  rescue Net::SMTPFatalError, Net::SMTPUnknownError, Net::SMTPSyntaxError => e
    Result.new(success: false, error_code: ERROR_CODES[:unknown], message: e.message)
  rescue StandardError => e
    Result.new(success: false, error_code: ERROR_CODES[:unknown], message: e.message)
  end
end
