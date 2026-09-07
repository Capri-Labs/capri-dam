# Mint, inspect and revoke external review links.
#
# WHO MAY CREATE ONE
# ------------------
# Not an administrator — the person who needs a client to look at a proof is
# the person who owns the work, and routing every review through an admin would
# guarantee the feature goes unused. But minting a link is a decision to send
# material outside the organisation, so it requires +:modify+ on the target
# rather than the +:read+ that ordinary commenting needs: being allowed to
# discuss an asset is not the same as being allowed to publish it.
#
# THE TOKEN IS RETURNED EXACTLY ONCE
# ----------------------------------
# Only its digest is stored (see {ReviewLink}), so the raw token in the +create+
# response is the only copy that will ever exist. A caller that loses it must
# revoke and mint again — which is the correct trade: it means a database
# compromise does not hand the attacker a set of working review URLs.
class Api::V1::ReviewLinksController < ApplicationController
  before_action :authenticate_hybrid!
  before_action :set_review_link, only: %i[show update destroy]

  # GET /api/v1/review_links
  #
  # Scoped to links the caller created unless they are an administrator, so a
  # user cannot enumerate what colleagues have shared externally.
  def index
    links = ReviewLink.includes(:asset, :collection, :created_by, :review_guests)
    links = links.where(created_by_id: current_user.id) unless current_user.admin?
    links = apply_status_filter(links)

    if params[:asset_id].present?
      links = links.where(asset_id: params[:asset_id])
    elsif params[:collection_id].present?
      links = links.where(collection_id: params[:collection_id])
    end

    links = links.order(created_at: :desc)
    render json: {
      review_links: links.map { |l| serialize(l) },
      meta: { total: links.size },
    }
  end

  # GET /api/v1/review_links/:id
  def show
    render json: serialize(@review_link, include_guests: true)
  end

  # POST /api/v1/review_links
  def create
    target = resolve_target
    return if performed?

    link, token = ReviewLink.mint(
      target: target,
      created_by: current_user,
      **link_params.to_h.symbolize_keys,
    )
    link.update!(passphrase: params[:passphrase]) if params[:passphrase].present?

    render json: serialize(link).merge(
      # The one and only time this value is ever visible.
      token: token,
      url: review_url(token: token),
    ), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PATCH /api/v1/review_links/:id
  #
  # Settings and expiry can be tightened or extended; the target cannot be
  # changed. Re-pointing a live link at a different asset would silently grant
  # an outsider access to material they were never shown, while the URL in
  # their inbox looks unchanged.
  def update
    @review_link.assign_attributes(link_params)
    @review_link.passphrase = params[:passphrase] if params.key?(:passphrase)
    @review_link.save!

    render json: serialize(@review_link)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # DELETE /api/v1/review_links/:id
  #
  # Revokes rather than deletes. The guest comments already collected point at
  # this row for their provenance — "who was this shown to, and under what
  # grant" is exactly the question an audit asks later — so the record stays and
  # only its usefulness as a credential ends.
  def destroy
    @review_link.revoke!
    render json: serialize(@review_link)
  end

  private

  def set_review_link
    @review_link = ReviewLink.find_by(id: params[:id])
    return render(json: { error: "Review link not found" }, status: :not_found) if @review_link.nil?

    return if current_user.admin? || @review_link.created_by_id == current_user.id

    # Someone else's outward grant is none of this user's business.
    render json: { error: "Review link not found" }, status: :not_found
  end

  def apply_status_filter(scope)
    case params[:status]
    when "active"  then scope.live
    when "revoked" then scope.where.not(revoked_at: nil)
    when "expired" then scope.where(revoked_at: nil).where("expires_at <= ?", Time.current)
    else scope
    end
  end

  # Resolves and authorises the thing being shared.
  #
  # Requires +:modify+, not +:read+ — see the class note.
  def resolve_target
    if params[:asset_id].present?
      asset = Asset.find_by(id: params[:asset_id])
      return render(json: { error: "Asset not found" }, status: :not_found) if asset.nil?

      check_asset_modify!(asset)
      performed? ? nil : asset
    elsif params[:collection_id].present?
      collection = Collection.find_by(id: params[:collection_id])
      return render(json: { error: "Collection not found" }, status: :not_found) if collection.nil?

      unless current_user.admin? || collection.user_id == current_user.id
        return render(json: { error: "You do not have permission to share this collection" }, status: :forbidden)
      end

      collection
    else
      render json: { error: "Either asset_id or collection_id is required" }, status: :unprocessable_entity
      nil
    end
  end

  def link_params
    params.permit(:name, :expires_at, :allow_comments, :allow_downloads, :require_email)
  end

  def review_url(token:)
    Rails.application.routes.url_helpers.review_url(
      token: token,
      host: request.host_with_port,
      protocol: request.protocol.delete_suffix("://"),
    )
  end

  # Never includes the token or its digest: the digest is a credential
  # equivalent for anyone who can reverse it and has no business leaving the
  # database.
  def serialize(link, include_guests: false)
    payload = {
      id: link.id,
      name: link.name,
      target_type: link.asset_id ? "asset" : "collection",
      target_id: link.asset_id || link.collection_id,
      target_label: link.target_label,
      asset_count: link.scoped_assets.count,
      expires_at: link.expires_at,
      revoked_at: link.revoked_at,
      status: link_status(link),
      allow_comments: link.allow_comments,
      allow_downloads: link.allow_downloads,
      require_email: link.require_email,
      passphrase_protected: link.passphrase_required?,
      access_count: link.access_count,
      last_accessed_at: link.last_accessed_at,
      guest_count: link.review_guests.size,
      comment_count: link.comment_threads.count,
      created_by: link.created_by && { id: link.created_by_id, name: link.created_by.name },
      created_at: link.created_at,
    }
    payload[:guests] = link.review_guests.order(:created_at).map { |g| serialize_guest(g) } if include_guests
    payload
  end

  def serialize_guest(guest)
    {
      id: guest.id,
      email: guest.anonymous? ? nil : guest.email,
      name: guest.name,
      display_name: guest.display_name,
      anonymous: guest.anonymous?,
      last_seen_at: guest.last_seen_at,
      comment_count: guest.comments.count,
    }
  end

  def link_status(link)
    return "revoked" if link.revoked_at.present?
    return "expired" unless link.expires_at&.future?

    "active"
  end
end
