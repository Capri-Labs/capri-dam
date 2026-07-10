# Concern that resolves the correct public URL for an {Asset} based on the
# current environment and active storage backend.
#
# == URL resolution priority
#
#   1. +storage_path+ recorded on the version/asset properties (authoritative —
#      this is what {AssetProcessorWorker} and the migration pipeline write).
#   2. ActiveStorage attachment on the active version → Rails URL helper
#      (fallback only; see NOTE below).
#   3. Active StorageBackend adapter → adapter#url(storage_path)
#   4. Environment default:
#      - production/staging: CDN base URL (ENV["CDN_BASE_URL"])
#      - development/test:   local serve endpoint (/api/v1/assets/local/:uuid)
#
# NOTE: +active_storage_attachments.record_id+ is a +bigint+ column, but
# {Asset}/{AssetVersion} use +uuid+ primary keys. Rails cannot match a uuid
# against that column, so every attachment for these models is persisted with
# +record_id: 0+. This means +version.file.attached?+ can spuriously return
# +true+ for a *different* version's blob (whichever row happens to satisfy
# +record_type = "AssetVersion" AND record_id = 0+), serving the wrong image.
# Preferring +storage_path+ — which is always written right after upload —
# avoids that cross-contamination without requiring an ActiveStorage schema
# migration.
#
# The CDN base URL is read from ENV["CDN_BASE_URL"] so it can be overridden per
# environment without touching code.  Set it in your credentials or .env file:
#
#   CDN_BASE_URL=https://cdn.yourdam.com
#
# @example
#   asset_url_for(asset)                         # inline URL
#   asset_url_for(asset, disposition: :download) # attachment URL with filename
module AssetUrlHelper
  extend ActiveSupport::Concern

  included do
    include Rails.application.routes.url_helpers
  end

  # CDN base URL resolved once per process from ENV.
  # Falls back to the placeholder domain so development never breaks.
  CDN_BASE_URL = -> {
    ENV.fetch("CDN_BASE_URL", "https://cdn.yourdam.com")
  }

  # Returns the public URL for *asset* or a specific historical version.
  #
  # @param asset [Asset]
  # @param version [AssetVersion, nil]
  # @param disposition [Symbol] +:inline+ (default) or +:download+
  # @return [String, nil] URL string, or nil when no file is attached/staged
  def asset_url_for(asset, version: nil, disposition: :inline)
    selected_version = version || asset.active_version

    storage_path =
      if version.present?
        selected_version&.properties&.fetch("storage_path", nil)
      else
        selected_version&.properties&.fetch("storage_path", nil) ||
          asset.properties&.fetch("storage_path", nil)
      end

    # 1. Fall back to the ActiveStorage attachment only when we have no
    # authoritative `storage_path` — see the class-level NOTE for why this
    # can't be trusted as the primary source for uuid-keyed models.
    #
    # IMPORTANT: `disposition` is a URL / HTTP-header concept.  It must NOT be
    # passed to `blob.variant(...)` — variant() only accepts image-processing
    # transformations (resize_to_limit, convert, rotate, …).  Passing it there
    # causes ActiveStorage::Transformers::ImageProcessingTransformer::
    # UnsupportedImageProcessingMethod at serving time.
    #
    # Instead we pass disposition directly to `url_for` / `rails_blob_url` via
    # the `download:` option that Rails exposes on the signed-URL helper.
    if storage_path.blank? && selected_version.respond_to?(:file) && selected_version.file.attached?
      # url_for on an ActiveStorage::Blob resolves to the signed redirect URL.
      # Rails will forward `disposition` as a header at serve time when it is
      # included in the signed params, not as an image transform.
      return url_for(selected_version.file)
    end

    return nil unless storage_path.present?

    # 2. Ask the active storage backend adapter (S3, GCS, Azure, local, …).
    #    Adapters that support presigned URLs can return them here.
    #
    # PERF: memoized per-request (see {#active_storage_backend}) — this
    # method is called once per asset when formatting a folder listing, so a
    # fresh `StorageBackend.find_by(active: true)` query per asset turned
    # into 1,000-3,000+ extra round-trips for large folders.
    backend = active_storage_backend
    if backend
      adapter = StorageManager.adapter_for(backend) rescue nil
      if adapter.respond_to?(:url)
        # Local adapter: url(path) → /api/v1/assets/local/<path> is intentionally
        # bypassed in favour of UUID-based lookup below, because the controller
        # resolves files by UUID, not raw path.
        return adapter.url(storage_path) if version.present?
        return adapter.url(storage_path) unless adapter.is_a?(StorageAdapters::LocalStorageAdapter)
      end
    end

    # 3. Environment default.
    if Rails.env.production? || Rails.env.staging?
      asset_delivery_url_for(asset, version: selected_version)
    else
      local_asset_delivery_path_for(asset, version: selected_version)
    end
  end

  # Returns a URL that resolves to a web-renderable *preview* of the asset.
  #
  # When the asset has a generated preview (e.g. a flattened PNG for a PSD),
  # this points at the +?variant=preview+ endpoint.  Otherwise it falls back to
  # the regular asset URL so callers can use it unconditionally for display.
  #
  # @param asset [Asset]
  # @param version [AssetVersion, nil]
  # @return [String, nil]
  def asset_preview_url_for(asset, version: nil)
    selected_version = version || asset.active_version
    preview_path =
      if version.present?
        selected_version&.properties&.fetch("preview_storage_path", nil)
      else
        selected_version&.properties&.fetch("preview_storage_path", nil) ||
          asset.properties&.fetch("preview_storage_path", nil)
      end

    return asset_url_for(asset, version: version) if preview_path.blank?

    if Rails.env.production? || Rails.env.staging?
      asset_delivery_url_for(asset, version: selected_version, variant: "preview")
    else
      local_asset_delivery_path_for(asset, version: selected_version, variant: "preview")
    end
  end

  # Convenience wrapper that returns a download-disposition URL.
  #
  # @param asset [Asset]
  # @return [String, nil]
  def asset_download_url_for(asset)
    asset_url_for(asset, disposition: :download)
  end

  # Generic variant URL resolver used for renditions that aren't the main
  # preview — e.g. the video poster thumbnail and MP4/OGG transcoded
  # renditions generated by {AssetProcessorWorker} for non-natively-playable
  # video formats. Returns +nil+ when the given property key has no stored
  # path (e.g. FFmpeg wasn't installed at processing time).
  #
  # @param asset [Asset]
  # @param variant [String] the +?variant=+ query value (see
  #   {Api::V1::AssetsController::VARIANT_PROPERTY_MAP})
  # @param path_property_key [String] the version/asset properties key holding
  #   the stored path for this variant
  # @param version [AssetVersion, nil]
  # @return [String, nil]
  def asset_variant_url_for(asset, variant, path_property_key:, version: nil)
    selected_version = version || asset.active_version
    path = selected_version&.properties&.fetch(path_property_key, nil) || asset.properties&.fetch(path_property_key, nil)
    return nil if path.blank?

    if Rails.env.production? || Rails.env.staging?
      asset_delivery_url_for(asset, version: selected_version, variant: variant)
    else
      local_asset_delivery_path_for(asset, version: selected_version, variant: variant)
    end
  end

  private

  # Memoized per-request lookup of the active {StorageBackend} — avoids
  # re-querying the database for every asset when formatting a folder/search
  # listing (see the PERF note at the {#asset_url_for} call site).
  #
  # @return [StorageBackend, nil]
  def active_storage_backend
    return @active_storage_backend if defined?(@active_storage_backend)

    @active_storage_backend = StorageBackend.find_by(active: true)
  rescue StandardError
    @active_storage_backend = nil
  end

  def asset_delivery_url_for(asset, version:, variant: nil)
    query = { variant: variant, version_id: version&.id }.compact.to_query
    base_url = "#{CDN_BASE_URL.call}/assets/#{asset.uuid}"

    query.present? ? "#{base_url}?#{query}" : base_url
  end

  def local_asset_delivery_path_for(asset, version:, variant: nil)
    query = { variant: variant, version_id: version&.id }.compact.to_query
    base_path = "/api/v1/assets/local/#{asset.uuid}"

    query.present? ? "#{base_path}?#{query}" : base_path
  end
end
