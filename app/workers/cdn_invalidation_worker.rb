class CdnInvalidationWorker
  include Sidekiq::Worker

  # 🚀 Isolate this away from the default and ingest queues
  sidekiq_options queue: "cdn_invalidation", retry: 5

  # Safety net to alert your DevOps team if a purge permanently fails
  sidekiq_retries_exhausted do |msg, exception|
    target_type = msg["args"][0]
    target_id = msg["args"][1]
    Rails.logger.error "💥 CDN Purge failed for #{target_type} #{target_id}: #{exception.message}"
  end

  def perform(target_type, target_id)
    tag = "#{target_type}-#{target_id}"
    CdnManager.purge_tag(tag)
    case target_type
    when "asset"
      purge_asset(target_id)
    when "folder"
      purge_folder(target_id)
    else
      Rails.logger.warn "⚠️ Unknown CDN purge target: #{target_type}"
    end
  end

  private

  def purge_asset(asset_uuid)
    # The canonical path the CMS is using
    paths_to_invalidate = [ "/assets/#{asset_uuid}/latest*" ]

    # Delegate to your CDN provider's API (e.g., Aws::CloudFront::Client)
    # CdnManager.invalidate_paths(paths_to_invalidate)

    Rails.logger.info "✅ CDN Purged for Asset: #{asset_uuid}"
  end

  def purge_folder(folder_id)
    folder = Folder.find_by(id: folder_id)
    return unless folder

    # If using Surrogate Keys/Cache Tags (Fastly/Cloudflare):
    # CdnManager.purge_tag("folder-#{folder.id}")

    # If using Path Wildcards (CloudFront):
    # Fetch all asset UUIDs in this folder and batch them
    asset_uuids = Asset.where(folder_id: folder.id).pluck(:uuid)

    paths_to_invalidate = asset_uuids.map { |uuid| "/assets/#{uuid}/latest*" }

    # CloudFront limits invalidations to 3,000 paths per batch, so we slice them
    paths_to_invalidate.each_slice(1000) do |batch|
      # CdnManager.invalidate_paths(batch)
    end

    Rails.logger.info "✅ CDN Purged for Folder: #{folder.name} (#{asset_uuids.count} assets)"
  end
end
