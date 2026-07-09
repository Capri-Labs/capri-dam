class SystemConnector < ApplicationRecord
  # Reference the standalone DamProviders constant — safe at class-load time
  # because app/lib/dam_providers.rb has no Rails/AR dependencies.
  PROVIDER_TYPES = DamProviders::KEYS

  # "token"               — simple Bearer/Basic auth_token (most adapters)
  # "jwt_service_account"  — Adobe IMS technical account, private-key JWT exchange
  CREDENTIAL_TYPES = %w[token jwt_service_account].freeze
  JWT_REQUIRED_FIELDS = %w[client_id client_secret private_key technical_account_id org_id ims_endpoint metascopes].freeze
  TOKEN_REFRESH_BUFFER = 10.minutes

  # 🚀 SECURITY BY DESIGN: secrets are encrypted at rest via Rails 8
  # ActiveRecord Encryption — the database only ever sees ciphertext.
  # `auth_token` covered legacy plaintext rows before this migration
  # (`support_unencrypted_data` stays enabled in dev/test for backfill safety).
  #
  # NOTE: `encrypts ..., type: :json` is NOT a valid option on this Rails
  # version (it silently corrupts the encryption context — see
  # ActiveRecord::Encryption::EncryptableRecord#encrypts). The correct way to
  # get JSON semantics on an encrypted column is to declare the attribute's
  # cast type first, then encrypt it with no extra options.
  attribute :credentials_payload, :json
  encrypts :auth_token
  encrypts :credentials_payload
  encrypts :access_token

  validates :name,          presence: true
  validates :provider_type, presence: true, inclusion: { in: PROVIDER_TYPES }
  validates :credential_type, inclusion: { in: CREDENTIAL_TYPES }
  # FTP connectors use a bare hostname (no http scheme), so we only enforce
  # URL format for HTTP-based providers.
  validates :endpoint, presence: true,
            format: { with: /\Ahttps?:\/\/.+\z/i, message: "must be a valid http(s) URL" },
            unless: -> { provider_type.to_s == "ftp" }
  validate :jwt_credentials_present, if: -> { credential_type == "jwt_service_account" }

  has_many :ingestion_batches, foreign_key: :connector_id, dependent: :nullify

  before_create :generate_webhook_secret

  # Test the live connection using the correct ingestion adapter (loaded lazily at runtime)
  def test_connection
    creds = credentials_for_adapter
    IngestionAdapters::Factory.test(provider_type, creds)
  rescue Ims::JwtTokenExchangeService::Error => e
    { success: false, message: e.message }
  rescue => e
    { success: false, message: e.message }
  end

  def provider_label
    DamProviders.label_for(provider_type)
  end

  # Credentials hash handed to IngestionAdapters — resolves a fresh IMS access
  # token on demand for jwt_service_account connectors, otherwise uses the
  # stored auth_token as-is.
  def credentials_for_adapter(source_path: nil)
    token = credential_type == "jwt_service_account" ? ensure_fresh_access_token! : auth_token
    {
      "endpoint"   => endpoint,
      "auth_token" => token,
      "root_path"  => (source_path.presence || default_source_path),
    }.compact
  end

  # @return [Boolean] true when the cached access token is present and not
  #   within TOKEN_REFRESH_BUFFER of expiring.
  def token_valid?
    access_token.present? && access_token_expires_at.present? &&
      access_token_expires_at > Time.current + TOKEN_REFRESH_BUFFER
  end

  # Returns a valid access token, transparently refreshing it first if it is
  # missing/expiring soon. No-op (returns auth_token) for non-JWT connectors.
  def ensure_fresh_access_token!
    return auth_token unless credential_type == "jwt_service_account"
    return access_token if token_valid?

    refresh_access_token!
  end

  # Forces a token refresh regardless of current expiry — used by the manual
  # "Refresh Token" admin action and the background auto-refresh worker.
  def refresh_access_token!
    result = Ims::JwtTokenExchangeService.new(self).call
    update!(
      access_token:            result[:access_token],
      access_token_expires_at: result[:expires_at],
      token_status:            "valid",
      last_token_refreshed_at: Time.current,
      last_token_error:        nil
    )
    access_token
  rescue Ims::JwtTokenExchangeService::Error => e
    update!(token_status: "error", last_token_error: e.message)
    raise
  end

  # Invalidates the cached access token locally. Adobe IMS has no public
  # "revoke this token" API for service accounts — true revocation requires
  # rotating the client secret / regenerating the key pair in the Adobe
  # Developer Console. This clears our cache so no further requests use it.
  def revoke_token!
    update!(access_token: nil, access_token_expires_at: nil, token_status: "revoked", last_token_error: nil)
  end

  def certificate_expiration_date
    credentials_payload&.dig("certificate_expiration_date")
  end

  # Never expose secrets over the API — credentials_payload/access_token are
  # ciphertext-backed but we still keep them out of JSON entirely.
  def as_json(options = {})
    super(options.merge(except: [ *Array(options[:except]), :credentials_payload, :access_token, :auth_token ]))
  end

  private

  def jwt_credentials_present
    missing = JWT_REQUIRED_FIELDS.select { |k| credentials_payload&.dig(k).blank? }
    errors.add(:credentials_payload, "is missing required field(s): #{missing.join(", ")}") if missing.any?
  end

  def generate_webhook_secret
    self.webhook_secret = SecureRandom.hex(32)
  end
end
