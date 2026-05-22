class TrashCleanupWorker
  include Sidekiq::Worker

  def perform
    threshold = 30.days.ago

    # Find items deleted more than 30 days ago
    expired_assets = Asset.trashed.where('deleted_at < ?', threshold)
    expired_folders = Folder.trashed.where('deleted_at < ?', threshold)

    expired_assets.find_each do |asset|
      # Trigger physical deletion logic here
      asset.destroy
    end

    expired_folders.find_each do |folder|
      folder.destroy
    end

    Rails.logger.info "🧹 Trash Cleanup: Removed #{expired_assets.count} assets and #{expired_folders.count} folders."
  end
end