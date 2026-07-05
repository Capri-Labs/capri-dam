# Strongly-typed data mapper around the `smtp_settings` row stored in the
# `settings` table (see Setting#apply_smtp_settings!). This is the single
# source of truth every mailer, worker, and controller must go through to
# read or persist outbound email configuration -- no other code should read
# `Setting.get("smtp_settings")` directly.
#
# The underlying `Setting.value` column is encrypted at rest (`encrypts :value,
# deterministic: false`), so `smtp_password` is never stored or transmitted to
# the database in plaintext.
class SystemEmailConfig
  include ActiveModel::Model
  include ActiveModel::Attributes

  SETTINGS_KEY = "smtp_settings".freeze
  SECURITY_PROTOCOLS = %w[none starttls ssl].freeze
  AUTHENTICATION_TYPES = %w[plain login cram_md5].freeze

  attribute :enabled, :boolean, default: false
  attribute :smtp_host, :string
  attribute :smtp_port, :integer, default: 587
  attribute :domain, :string
  attribute :smtp_username, :string
  attribute :smtp_password, :string
  attribute :security_protocol, :string, default: "starttls"
  attribute :authentication, :string, default: "plain"
  attribute :default_from_address, :string
  attribute :default_from_name, :string

  validates :smtp_host, :smtp_port, presence: true, if: :enabled
  validates :security_protocol, inclusion: { in: SECURITY_PROTOCOLS }
  validates :authentication, inclusion: { in: AUTHENTICATION_TYPES }, allow_blank: true
  validates :default_from_address, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  # Loads the currently persisted configuration from the database.
  def self.current
    from_raw(Setting.get(SETTINGS_KEY))
  end

  # Builds an instance from the loosely-typed hash shape historically stored
  # by the settings UI/controller (string booleans, `address`/`port`, etc.)
  def self.from_raw(raw)
    raw = raw.is_a?(Hash) ? raw.stringify_keys : {}

    new(
      enabled: raw["enabled"].to_s == "true",
      smtp_host: raw["address"],
      smtp_port: (raw["port"].presence || 587).to_i,
      domain: raw["domain"],
      smtp_username: raw["user_name"],
      smtp_password: raw["password"],
      security_protocol: raw["security_protocol"].presence || (raw["enable_starttls_auto"] == "true" ? "starttls" : "none"),
      authentication: raw["authentication"].presence || "plain",
      default_from_address: raw["sender_address"],
      default_from_name: raw["sender_name"]
    )
  end

  # Validates and persists the configuration, then re-applies it to
  # ActionMailer so the change takes effect immediately.
  def persist!
    return false unless valid?

    Setting.set(SETTINGS_KEY, to_settings_hash)
    apply!
    true
  end

  # Serializes back to the legacy hash shape consumed by
  # Setting.apply_smtp_settings! and the React settings UI.
  def to_settings_hash
    {
      "enabled" => enabled.to_s,
      "address" => smtp_host,
      "port" => smtp_port.to_s,
      "domain" => domain,
      "user_name" => smtp_username,
      "password" => smtp_password,
      "authentication" => authentication,
      "enable_starttls_auto" => (security_protocol == "starttls").to_s,
      "security_protocol" => security_protocol,
      "sender_address" => default_from_address,
      "sender_name" => default_from_name,
    }
  end

  # Re-applies whatever is currently persisted in the database to
  # ActionMailer::Base. Kept as a thin delegate so there remains exactly one
  # implementation of the ActionMailer wiring logic (Setting.apply_smtp_settings!).
  def apply!
    Setting.apply_smtp_settings!
  end

  # Options shape consumed by Net::SMTP / SmtpConnectionValidator.
  def net_smtp_options
    {
      address: smtp_host,
      port: smtp_port,
      domain: domain.presence || "localhost",
      user_name: smtp_username,
      password: smtp_password,
      authentication: authentication.presence&.to_sym || :plain,
      enable_starttls_auto: security_protocol == "starttls",
      ssl: security_protocol == "ssl",
    }
  end

  # Resolves the effective outbound "From" header, falling back to an
  # environment default when no database value has been configured yet.
  def from_address_with_name
    address = default_from_address.presence || ENV.fetch("MAILER_SENDER_ADDRESS", "noreply@yourdam.com")
    default_from_name.present? ? "#{default_from_name} <#{address}>" : address
  end

  def persisted?
    true
  end
end
