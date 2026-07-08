# Serves a **read-only, unauthenticated** snapshot of a {Collection} to
# anyone holding a valid share link (see {Api::V1::CollectionsController#create_share_link}
# and {Collection#generate_share_token}). No Devise/OAuth session is required —
# the signed token itself is the credential, and it is re-validated (and can
# expire or be tampered-detected) on every request.
#
# @see Collection#generate_share_token
# @see Collection#find_by_share_token
module Public
  class CollectionSharesController < ApplicationController
    include AssetUrlHelper

    layout "public_share"
    helper_method :asset_preview_url_for

    # GET /s/collections/:token
    def show
      @collection = Collection.find_by_share_token(params[:token])

      if @collection.nil? || @collection.deleted_at.present?
        render :invalid, status: :gone
        return
      end

      @token  = params[:token]
      @assets = @collection.assets.order(created_at: :desc)
    end
  end
end
