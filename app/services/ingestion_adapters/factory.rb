require_relative "aem_adapter"
require_relative "bynder_adapter"
require_relative "widen_adapter"
require_relative "canto_adapter"
require_relative "media_valet_adapter"
require_relative "brandfolder_adapter"
require_relative "cloudinary_adapter"
require_relative "nuxeo_adapter"
require_relative "aprimo_adapter"
require_relative "extensis_adapter"
require_relative "sharepoint_adapter"
require_relative "ftp_adapter"

module IngestionAdapters
  class Factory
    ADAPTERS = {
      "aem"         => "IngestionAdapters::AemAdapter",
      "bynder"      => "IngestionAdapters::BynderAdapter",
      "widen"       => "IngestionAdapters::WidenAdapter",
      "canto"       => "IngestionAdapters::CantoAdapter",
      "mediavalet"  => "IngestionAdapters::MediaValetAdapter",
      "brandfolder" => "IngestionAdapters::BrandfolderAdapter",
      "cloudinary"  => "IngestionAdapters::CloudinaryAdapter",
      "nuxeo"       => "IngestionAdapters::NuxeoAdapter",
      "aprimo"      => "IngestionAdapters::AprimoAdapter",
      "extensis"    => "IngestionAdapters::ExtensisAdapter",
      "sharepoint"  => "IngestionAdapters::SharepointAdapter",
      "legacy_s3"   => "IngestionAdapters::S3Adapter",
      "ftp"         => "IngestionAdapters::FtpAdapter",
    }.freeze

    def self.build(batch)
      source_type  = batch.source_type.to_s
      credentials  = resolve_credentials(batch)
      klass_name   = ADAPTERS[source_type]
      raise ArgumentError, "Unknown migration source '#{source_type}'. Supported: #{ADAPTERS.keys.join(", ")}" unless klass_name
      klass_name.constantize.new(batch, credentials)
    end

    # Test connection without a batch — used by SystemConnectorsController
    def self.test(provider_type, credentials)
      klass_name = ADAPTERS[provider_type.to_s]
      raise ArgumentError, "Unknown provider: #{provider_type}" unless klass_name
      klass_name.constantize.new(nil, credentials).test_connection
    rescue => e
      { success: false, message: e.message }
    end

    private

    def self.resolve_credentials(batch)
      # Prefer credentials stored inline on the batch (from the UI form),
      # then fall back to the linked connector's auth token and endpoint.
      creds = batch.respond_to?(:source_credentials) ? (batch.source_credentials || {}) : {}
      creds = creds.transform_keys(&:to_s)

      if creds.blank? && batch.respond_to?(:connector) && batch.connector.present?
        connector = batch.connector
        creds = {
          "endpoint"   => connector.endpoint,
          "auth_token" => connector.auth_token,
        }
      end

      creds
    end
  end
end
