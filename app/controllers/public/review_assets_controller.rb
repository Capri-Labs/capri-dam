module Public
  # Streams asset bytes to a guest holding a {ReviewLink}.
  #
  # The proxying rationale, the rights refusal and the storage-path resolution
  # are shared with the distribution portal and live in {GuestAssetStreaming}.
  class ReviewAssetsController < ApplicationController
    include ReviewLinkAuthentication
    include GuestAssetStreaming

    # Review tokens only; a portal token routed here would be granted commenting
    # and the collection-wide scope that portal grants exist to narrow.
    serves_link_kind :review

    rate_limit to: 240, within: 1.minute

    # GET /s/reviews/:token/assets/:asset_id/preview
    def preview
      asset = scoped_asset(params[:asset_id])
      return head(:not_found) if asset.nil?
      return if refuse_on_rights!(asset)

      stream(asset, path: preview_path_for(asset), disposition: "inline")
    end

    # GET /s/reviews/:token/assets/:asset_id/download
    def download
      asset = scoped_asset(params[:asset_id])
      return head(:not_found) if asset.nil?
      # Separately gated: being invited to comment on something is not the
      # same as being allowed to keep a copy of it.
      return head(:forbidden) unless @review_link.allow_downloads?
      return if refuse_on_rights!(asset)

      stream(asset,
             path: original_path_for(asset),
             disposition: "attachment",
             filename: asset.title)
    end
  end
end
