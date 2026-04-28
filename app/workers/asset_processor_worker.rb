class AssetProcessorWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'ingest', retry: 3

  def perform(asset_id, staging_path = nil)
    asset = Asset.find_by(id: asset_id)
    return unless asset

    asset.update!(status: 'processing')
    backend = ::StorageBackend.find_by(active: true)
    storage = ::StorageManager.adapter_for(backend)

    # 1. Extract the extension from the original filename (e.g., ".png")
    # We fall back to an empty string if it's missing
    extension = File.extname(asset.properties['original_filename'] || "").downcase

    # 2. Build a better storage path: UUID/original + extension
    # This keeps the file "anonymous" on disk but technically correct
    file_path = "#{asset.uuid}/original#{extension}"

    if staging_path && File.exist?(staging_path)
      File.open(staging_path, 'rb') do |file|
        storage.store(file, file_path)
      end
      File.delete(staging_path)
    else
      # Mock logic for batch testing
      dummy_content = StringIO.new("Mock data")
      storage.store(dummy_content, file_path)
    end

    asset.update!(
      status: 'ready',
      properties: asset.properties.merge(
        storage_path: file_path,
        extension: extension,
        processed_at: Time.current
      )
    )

    Rails.logger.info "✅ Asset #{asset.uuid} stored as #{file_path}"
  end
end