class FolderMetadataSyncWorker
  include Sidekiq::Worker

  # Low priority queue so manual mass-syncs don't block critical live uploads
  sidekiq_options queue: "edge_metadata_bulk", retry: 3

  def perform(folder_id)
    folder = Folder.active.find_by(id: folder_id)
    return unless folder

    # 🚀 The Fan-Out: Find all active assets in this folder and queue them
    # using find_each to load records in batches of 1000, preventing memory bloat.
    Asset.active.where(folder_id: folder.id).select(:uuid).find_each do |asset|
      EdgeMetadataSyncWorker.perform_async(asset.uuid)
    end

    # Optional: If you want this to be recursive (syncing subfolders too)
    Folder.active.where(parent_id: folder.id).select(:id).find_each do |subfolder|
      FolderMetadataSyncWorker.perform_async(subfolder.id)
    end
  end
end
