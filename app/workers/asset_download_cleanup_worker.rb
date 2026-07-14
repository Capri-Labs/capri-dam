class AssetDownloadCleanupWorker
  include Sidekiq::Worker

  sidekiq_options queue: "default", retry: 1

  # Purges expired ZIP downloads (older than AssetDownload::RETENTION_PERIOD).
  # Removes the attached ZIP blob and the download record itself.
  def perform
    AssetDownload.expired.find_each do |download|
      download.zip_file.purge if download.zip_file.attached?
      download.destroy
    rescue StandardError => e
      Rails.logger.error "⚠️ Failed to clean up asset download ##{download.id}: #{e.message}"
    end
  end
end
