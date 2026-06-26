class SystemConnector < ApplicationRecord
  # Reference the standalone DamProviders constant — safe at class-load time
  # because app/lib/dam_providers.rb has no Rails/AR dependencies.
  PROVIDER_TYPES = DamProviders::KEYS

  validates :name,          presence: true
  validates :provider_type, presence: true, inclusion: { in: PROVIDER_TYPES }
  # FTP connectors use a bare hostname (no http scheme), so we only enforce
  # URL format for HTTP-based providers.
  validates :endpoint, presence: true,
            format: { with: /\Ahttps?:\/\/.+\z/i, message: "must be a valid http(s) URL" },
            unless: -> { provider_type.to_s == "ftp" }

  has_many :ingestion_batches, foreign_key: :connector_id, dependent: :nullify

  before_create :generate_webhook_secret

  # Test the live connection using the correct ingestion adapter (loaded lazily at runtime)
  def test_connection
    creds = { "endpoint" => endpoint, "auth_token" => auth_token }
    IngestionAdapters::Factory.test(provider_type, creds)
  rescue => e
    { success: false, message: e.message }
  end

  def provider_label
    DamProviders.label_for(provider_type)
  end

  private

  def generate_webhook_secret
    self.webhook_secret = SecureRandom.hex(32)
  end
end
