module Public
  # Streams asset bytes to a partner collecting files from a distribution
  # portal, and records what they took.
  #
  # DOWNLOAD IS GATED FOUR TIMES
  # ----------------------------
  # 1. The asset must be in the link's scope — still in the collection *and*
  #    explicitly granted (see {ReviewLink#scoped_assets}).
  # 2. The asset must be cleared for external release by
  #    {Rights::DownloadPolicy}.
  # 3. The grant itself must say +download+ and not merely +view+.
  # 4. The link must still be live, which {ReviewLinkAuthentication} rechecks
  #    on every request.
  #
  # None of these is redundant. Scope answers "was this shared", rights answers
  # "may it lawfully leave", the grant answers "was it shared *to be taken*",
  # and liveness answers "is that still true right now".
  class PortalAssetsController < ApplicationController
    include ReviewLinkAuthentication
    include GuestAssetStreaming

    serves_link_kind :portal

    rate_limit to: 240, within: 1.minute

    # GET /s/portal/:token/assets/:asset_id/preview
    def preview
      asset = portal_asset
      return head(:not_found) if asset.nil?
      return if refuse_on_rights!(asset)

      stream(asset, path: preview_path_for(asset), disposition: "inline")
    end

    # GET /s/portal/:token/assets/:asset_id/download
    def download
      asset = portal_asset
      return head(:not_found) if asset.nil?
      # A view-only grant is refused outright. This is a 403 rather than a 404
      # because, unlike a restricted asset, the guest can already see the file
      # in their portal — pretending it does not exist would only confuse
      # somebody who is looking straight at it.
      return head(:forbidden) unless @review_link.may_download?(asset)
      return if refuse_on_rights!(asset)

      delivered = stream(asset,
                         path: original_path_for(asset),
                         disposition: "attachment",
                         filename: asset.title)

      # Only a completed handover is recorded. A log of attempts answers a
      # much less useful question than a log of deliveries.
      return unless delivered

      PortalDownload.record!(
        review_link: @review_link,
        asset: asset,
        guest: current_review_guest,
        request: request,
      )
    end

    private

    # Resolves an asset *within the portal's scope*, so a partner cannot pivot
    # to an asset they were not given by editing the id in the URL.
    #
    # Goes through {ReviewLink#distributable_assets}, so an asset withheld by
    # rights is indistinguishable from one that was never granted: both 404.
    def portal_asset
      id = params[:asset_id]
      return nil if id.blank?

      @review_link.distributable_assets.find_by(id: id)
    end
  end
end
