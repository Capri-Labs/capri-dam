# High-throughput bulk asset ingestion service.
#
# Uses a single +INSERT ALL+ statement to create many {Asset} rows at once,
# bypassing the overhead of individual ActiveRecord +create+ calls.  Each
# inserted asset is then handed off to {AssetProcessorWorker} for asynchronous
# binary processing.
#
# This service is suitable for large batch imports (e.g. onboarding an existing
# media library) where the overhead of per-file HTTP uploads is unacceptable.
#
# @example
#   files = [
#     { filename: "hero.jpg",    size: 204800 },
#     { filename: "banner.png",  size: 102400 }
#   ]
#   BatchIngestService.call(current_user, target_folder, files)
#   # => 2
#
# @see AssetProcessorWorker
class BatchIngestService
  # Bulk-inserts assets and enqueues processing workers for each one.
  #
  # @param user               [User]   the owner to stamp on every new asset
  # @param folder             [Folder] the target folder for all assets
  # @param file_metadata_list [Array<Hash>] each entry must have:
  #   * +:filename+ [String]  — the original filename
  #   * +:size+     [Integer] — file size in bytes
  # @return [Integer] the number of assets successfully inserted
  def self.call(user, folder, file_metadata_list)
    Rails.logger.info "--- [BatchIngest] Starting ingest for #{file_metadata_list.count} files ---"

    # Build the bulk-insert payload
    assets_to_insert = file_metadata_list.map do |file|
      {
        user_id:    user.id,
        folder_id:  folder.id,
        title:      file[:filename],
        status:     "pending",
        uuid:       SecureRandom.uuid,
        properties: { original_filename: file[:filename], size: file[:size] },
        created_at: Time.current,
        updated_at: Time.current,
      }
    end

    # Single SQL statement — no callbacks, no validations, maximum throughput
    result = Asset.insert_all(assets_to_insert, returning: %w[id])

    # Enqueue a processing worker for each newly created asset
    result.each do |row|
      AssetProcessorWorker.perform_async(row["id"])
    end

    result.count
  end
end
