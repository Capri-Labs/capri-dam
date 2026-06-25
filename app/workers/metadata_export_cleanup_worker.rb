class MetadataExportCleanupWorker
  include Sidekiq::Worker

  sidekiq_options queue: "default", retry: 1

  # Purges expired exports (older than MetadataExport::RETENTION_PERIOD).
  # Removes the attached CSV blobs and the export record itself.
  def perform
    MetadataExport.expired.find_each do |export|
      export.files.purge if export.files.attached?
      export.destroy
    rescue StandardError => e
      Rails.logger.error "⚠️ Failed to clean up metadata export ##{export.id}: #{e.message}"
    end
  end
end
