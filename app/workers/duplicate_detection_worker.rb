# Sidekiq worker that runs {DuplicateDetectionService} asynchronously after
# an asset version has been fully processed (i.e. after {AssetProcessorWorker}
# has extracted the SHA-256 checksum and written it into
# +asset_versions.properties['checksum_sha256']+).
#
# == Queue & retry policy
#
# * Queue:   +duplicate_detection+
# * Retries: 2 (SHA-256 lookups are cheap; excessive retry not needed)
# * Uniqueness: none — the service itself is idempotent (find_or_create_by)
#
# == Usage
#
#   DuplicateDetectionWorker.perform_async(asset_id, checksum, user_id)
#
# @see DuplicateDetectionService
# @see AssetProcessorWorker
class DuplicateDetectionWorker
  include Sidekiq::Worker
  sidekiq_options queue: "duplicate_detection", retry: 2

  # @param asset_id  [String]  UUID of the processed {Asset}
  # @param checksum  [String]  SHA-256 hex digest
  # @param user_id   [Integer] ID of the {User} who uploaded the asset
  # @return [void]
  def perform(asset_id, checksum, user_id)
    asset = Asset.find_by(id: asset_id)
    user  = User.find_by(id: user_id)

    unless asset
      Rails.logger.warn "[DuplicateDetectionWorker] Asset #{asset_id} not found, skipping."
      return
    end

    result = DuplicateDetectionService.call(
      asset:    asset,
      checksum: checksum,
      user:     user,
    )

    if result.duplicate_detected?
      Rails.logger.info(
        "[DuplicateDetectionWorker] Duplicate group #{result.duplicate_group.id} " \
        "updated — #{result.new_duplicates} new member(s) added."
      )
    else
      Rails.logger.info(
        "[DuplicateDetectionWorker] No duplicates found for asset #{asset_id} " \
        "(enabled=#{result.enabled})."
      )
    end
  rescue StandardError => e
    Rails.logger.error(
      "[DuplicateDetectionWorker] Unhandled error for asset #{asset_id}: #{e.class}: #{e.message}"
    )
    raise
  end
end
