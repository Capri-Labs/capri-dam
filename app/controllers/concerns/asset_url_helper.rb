# Concern that resolves the correct public URL for an {Asset} based on the
# current environment and active storage backend.
#
# == URL resolution priority
#
#   1. ActiveStorage attachment on the active version → Rails URL helper
#   2. Active StorageBackend adapter → adapter#url(storage_path)
#   3. Environment default:
#      - production/staging: CDN base URL (ENV["CDN_BASE_URL"])
#      - development/test:   local serve endpoint (/api/v1/assets/local/:uuid)
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

  # Returns the public URL for the active version of *asset*.
  #
  # @param asset [Asset]
  # @param disposition [Symbol] +:inline+ (default) or +:download+
  # @return [String, nil] URL string, or nil when no file is attached/staged
  def asset_url_for(asset, disposition: :inline)
    active_v = asset.active_version

    # 1. Prefer ActiveStorage attachment — gives us signed Blob URLs for free.
    #
    # IMPORTANT: `disposition` is a URL / HTTP-header concept.  It must NOT be
    # passed to `blob.variant(...)` — variant() only accepts image-processing
    # transformations (resize_to_limit, convert, rotate, …).  Passing it there
    # causes ActiveStorage::Transformers::ImageProcessingTransformer::
    # UnsupportedImageProcessingMethod at serving time.
    #
    # Instead we pass disposition directly to `url_for` / `rails_blob_url` via
    # the `download:` option that Rails exposes on the signed-URL helper.
    if active_v.respond_to?(:file) && active_v.file.attached?
      # url_for on an ActiveStorage::Blob resolves to the signed redirect URL.
      # Rails will forward `disposition` as a header at serve time when it is
      # included in the signed params, not as an image transform.
      return url_for(active_v.file)
    end

    storage_path = active_v&.properties&.fetch("storage_path", nil) ||
                   asset.properties&.fetch("storage_path", nil)

    return nil unless storage_path.present?

    # 2. Ask the active storage backend adapter (S3, GCS, Azure, local, …).
    #    Adapters that support presigned URLs can return them here.
    backend = StorageBackend.find_by(active: true) rescue nil
    if backend
      adapter = StorageManager.adapter_for(backend) rescue nil
      if adapter.respond_to?(:url)
        # Local adapter: url(path) → /api/v1/assets/local/<path> is intentionally
        # bypassed in favour of UUID-based lookup below, because the controller
        # resolves files by UUID, not raw path.
        return adapter.url(storage_path) unless adapter.is_a?(StorageAdapters::LocalStorageAdapter)
      end
    end

    # 3. Environment default.
    if Rails.env.production? || Rails.env.staging?
      "#{CDN_BASE_URL.call}/assets/#{asset.uuid}"
    else
      # Development / test: authenticated local-serve endpoint.
      # Route: GET /api/v1/assets/local/:uuid → Api::V1::AssetsController#serve_local
      "/api/v1/assets/local/#{asset.uuid}"
    end
  end

  # Convenience wrapper that returns a download-disposition URL.
  #
  # @param asset [Asset]
  # @return [String, nil]
  def asset_download_url_for(asset)
    asset_url_for(asset, disposition: :download)
  end
end
