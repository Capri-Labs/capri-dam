module Public
  # Streams asset bytes to a guest holding a {ReviewLink}.
  #
  # WHY PROXY RATHER THAN HAND OUT A URL
  # ------------------------------------
  # The internal app resolves previews to a CDN or signed storage URL. Giving
  # one of those to a guest would defeat revocation: the signed URL keeps
  # working for its own lifetime no matter what happens to the review link, so
  # "withdraw this client's access" would not actually withdraw anything.
  #
  # Streaming through this controller means every single byte a guest receives
  # is re-authorised against the live link. Revoke it and the next image
  # request fails, which is the behaviour a revoke button has to have to be
  # worth having.
  class ReviewAssetsController < ApplicationController
    include ReviewLinkAuthentication

    rate_limit to: 240, within: 1.minute

    # GET /s/reviews/:token/assets/:asset_id/preview
    def preview
      asset = scoped_asset(params[:asset_id])
      return head(:not_found) if asset.nil?

      stream(asset, path: preview_path_for(asset), disposition: "inline")
    end

    # GET /s/reviews/:token/assets/:asset_id/download
    def download
      asset = scoped_asset(params[:asset_id])
      return head(:not_found) if asset.nil?
      # Separately gated: being invited to comment on something is not the
      # same as being allowed to keep a copy of it.
      return head(:forbidden) unless @review_link.allow_downloads?

      stream(asset,
             path: original_path_for(asset),
             disposition: "attachment",
             filename: asset.title)
    end

    private

    # Storage paths live in the +properties+ JSON, on the active version first
    # and the asset second — the same resolution order the internal asset
    # download uses.
    def preview_path_for(asset)
      version = asset.active_version
      version&.properties&.dig("preview_storage_path").presence ||
        asset.properties&.dig("preview_storage_path").presence ||
        original_path_for(asset)
    end

    def original_path_for(asset)
      asset.active_version&.properties&.dig("storage_path").presence ||
        asset.properties&.dig("storage_path").presence
    end

    def stream(asset, path:, disposition:, filename: nil)
      return head(:not_found) if path.blank?

      data = StorageManager.read_file_from_adapter(path)
      return head(:not_found) if data.blank?

      send_data data,
                type: asset.properties&.dig("content_type").presence || "application/octet-stream",
                disposition: disposition,
                filename: filename.presence || File.basename(path)
    rescue StandardError => e
      # A missing or unreachable object is a 404 to the guest, not a stack
      # trace. The detail belongs in the log, not in an unauthenticated
      # response.
      Rails.logger.warn("[Public::ReviewAssets] #{asset.id} #{path}: #{e.class}: #{e.message}")
      head :not_found
    end
  end
end
