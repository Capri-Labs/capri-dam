class BatchIngestService
  def self.call(user, folder, file_metadata_list)

    Rails.logger.info "--- [BatchIngest] Starting ingest for #{file_metadata_list.count} files ---"
    # 1. Prepare the data for bulk insertion
    assets_to_insert = file_metadata_list.map do |file|
      {
        user_id: user.id,
        folder_id: folder.id,
        title: file[:filename],
        status: 'pending',
        uuid: SecureRandom.uuid,
        properties: { original_filename: file[:filename], size: file[:size] },
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    # 2. Execute Bulk Insert (Fast!)
    result = Asset.insert_all(assets_to_insert, returning: %w[id])

    # 3. Queue the background processing
    result.each do |row|
      AssetProcessorWorker.perform_async(row['id'])
    end

    result.count
  end
end