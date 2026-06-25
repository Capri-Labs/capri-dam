# DamProviders — Central registry of supported migration source systems.
#
# This file is intentionally framework-agnostic (no Rails/ActiveRecord references)
# so it can be safely referenced by both ActiveRecord models (at class-load time)
# and service classes (at runtime) without causing autoload order errors.
#
# Stored in app/lib/ so Rails autoloads it on first reference.

module DamProviders
  # Maps source_type / provider_type keys → human-readable labels.
  # Used for:
  #   - SystemConnector validation (PROVIDER_TYPES)
  #   - IngestionBatch display labels (source_label)
  #   - ConnectorCard / ConnectorDialog frontend labels
  #   - MigrationReportWorker summary stats
  LABELS = {
    "aem"          => "Adobe Experience Manager",
    "bynder"       => "Bynder",
    "widen"        => "Acquia DAM (Widen)",
    "canto"        => "Canto",
    "mediavalet"   => "MediaValet",
    "brandfolder"  => "Brandfolder",
    "cloudinary"   => "Cloudinary",
    "nuxeo"        => "Nuxeo Platform",
    "aprimo"       => "Aprimo DAM",
    "extensis"     => "Extensis Portfolio",
    "sharepoint"   => "Microsoft SharePoint",
    "legacy_s3"    => "AWS S3 Bucket",
    "ftp"          => "FTP / SFTP",
  }.freeze

  KEYS = LABELS.keys.freeze

  def self.label_for(provider_type)
    LABELS[provider_type.to_s] || provider_type.to_s
  end
end
