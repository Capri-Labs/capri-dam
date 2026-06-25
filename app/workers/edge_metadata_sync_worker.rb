class EdgeMetadataSyncWorker
  include Sidekiq::Worker

  # 🚀 Isolate this in a dedicated queue so massive metadata updates
  # don't block image processing or cache purges.
  sidekiq_options queue: "edge_metadata", retry: 5

  def perform(asset_uuid)
    asset = Asset.includes(:active_version).find_by(uuid: asset_uuid)
    return unless asset

    # 1. Compile the Edge Payload
    # We only push what the Edge or CMS actually needs to render the page,
    # keeping the KV store footprint extremely lightweight.
    active_v = asset.active_version
    properties = asset.properties.merge(active_v&.properties || {})

    payload = {
      uuid: asset.uuid,
      status: asset.status,
      version: active_v&.version_number || 1,
      alt_text: properties["alt_text"] || asset.title,
      content_type: properties["content_type"],
      focal_point: properties.dig("editor_state", "geometry", "focal_point") || { x: 50, y: 50 },
      color_space: properties["color_space"],
      # Extract only the 3 most prominent colors if you have an AI palette array
      dominant_colors: (properties["color_palette"] || []).first(3),
    }

    # 2. Hand off to the Agnostic Manager
    success = CdnManager.sync_metadata(asset.uuid, payload.to_json)

    raise "Edge Metadata Sync Failed for #{asset.uuid}" unless success
  end
end
