class MetadataImportCleanupWorker
  include Sidekiq::Worker

  sidekiq_options queue: "default", retry: 1

  # Purges expired imports (older than MetadataImport::RETENTION_PERIOD),
  # removing the attached source/result CSV blobs and the record itself.
  def perform
    MetadataImport.expired.find_each do |import|
      import.source_file.purge if import.source_file.attached?
      import.result_file.purge if import.result_file.attached?
      import.destroy
    rescue StandardError => e
      Rails.logger.error "⚠️ Failed to clean up metadata import ##{import.id}: #{e.message}"
    end
  end
end
