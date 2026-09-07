# Mint, configure and revoke **distribution portals**.
#
# WHY THIS IS NOT PART OF Api::V1::ReviewLinksController
# ------------------------------------------------------
# The two share a table and a credential, not a permission model. A review link
# is configured by answering "may they comment?"; a portal is configured by
# choosing, asset by asset, what may be taken. Serving both from one controller
# would mean every response carried settings that were meaningless for half its
# callers, and the grant editing that matters here would be bolted onto an
# endpoint whose contract is about something else.
#
# WHO MAY CREATE ONE
# ------------------
# The same rule as a review link, and for the same reason: minting a portal is
# a decision to send material outside the organisation, so it needs +:modify+
# on the target rather than +:read+. Being allowed to look at a collection is
# not the same as being allowed to hand it to a partner.
#
# GRANTS CANNOT WIDEN RIGHTS
# --------------------------
# A grant records that the sender is willing. Whether the asset may lawfully
# leave is {Rights::DownloadPolicy}'s question and is asked independently at
# delivery. Granting +download+ on an internal-only asset is therefore allowed
# to be *recorded* but will never be honoured — and the serializer reports it,
# so the person configuring the portal can see that three of their twelve
# picks will not actually be shared.
class Api::V1::PortalsController < ApplicationController
  before_action :authenticate_hybrid!
  before_action :set_portal, only: %i[show update destroy downloads]

  # GET /api/v1/portals
  #
  # Scoped to portals the caller created unless they are an administrator, so a
  # user cannot enumerate what colleagues have shared externally.
  def index
    portals = ReviewLink.portals.includes(:collection, :asset, :created_by, :portal_grants)
    portals = portals.where(created_by_id: current_user.id) unless current_user.admin?
    portals = apply_status_filter(portals).order(created_at: :desc)

    render json: {
      portals: portals.map { |p| serialize(p) },
      meta: { total: portals.size },
    }
  end

  # GET /api/v1/portals/:id
  def show
    render json: serialize(@portal, include_assets: true)
  end

  # POST /api/v1/portals
  def create
    target = resolve_target
    return if performed?

    portal, token = ReviewLink.mint(
      target: target,
      created_by: current_user,
      kind: "portal",
      **portal_params.to_h.symbolize_keys,
    )
    portal.update!(passphrase: params[:passphrase]) if params[:passphrase].present?
    apply_grants!(portal, params[:grants]) if params[:grants].present?

    render json: serialize(portal, include_assets: true).merge(
      # The one and only time this value is ever visible.
      token: token,
      url: portal_url_for(token: token),
    ), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PATCH /api/v1/portals/:id
  #
  # Settings, branding, expiry and grants can all be changed; the target cannot.
  # Re-pointing a live portal at a different collection would silently hand an
  # outsider material they were never shown, while the URL in their inbox looks
  # unchanged.
  def update
    @portal.assign_attributes(portal_params)
    @portal.passphrase = params[:passphrase] if params.key?(:passphrase)
    @portal.save!
    apply_grants!(@portal, params[:grants]) if params.key?(:grants)

    render json: serialize(@portal.reload, include_assets: true)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # DELETE /api/v1/portals/:id
  #
  # Revokes rather than deletes. The download records already collected point
  # at this row for their provenance — "who was sent what, and under what
  # grant" is exactly the question an audit asks later — so the record stays
  # and only its usefulness as a credential ends.
  def destroy
    @portal.revoke!
    render json: serialize(@portal)
  end

  # GET /api/v1/portals/:id/downloads
  #
  # The distribution record: what actually left, and to whom.
  def downloads
    records = @portal.portal_downloads.includes(:asset, :review_guest).order(created_at: :desc).limit(500)

    render json: {
      downloads: records.map { |d| serialize_download(d) },
      meta: { total: @portal.portal_downloads.count },
    }
  end

  private

  def set_portal
    @portal = ReviewLink.portals.find_by(id: params[:id])
    return render(json: { error: "Portal not found" }, status: :not_found) if @portal.nil?

    return if current_user.admin? || @portal.created_by_id == current_user.id

    # Someone else's outward grant is none of this user's business.
    render json: { error: "Portal not found" }, status: :not_found
  end

  def apply_status_filter(scope)
    case params[:status]
    when "active"  then scope.live
    when "revoked" then scope.where.not(revoked_at: nil)
    when "expired" then scope.where(revoked_at: nil).where("expires_at <= ?", Time.current)
    else scope
    end
  end

  # Resolves and authorises the thing being shared. Requires +:modify+.
  def resolve_target
    if params[:collection_id].present?
      collection = Collection.find_by(id: params[:collection_id])
      return render(json: { error: "Collection not found" }, status: :not_found) if collection.nil?

      unless current_user.admin? || collection.user_id == current_user.id
        return render(json: { error: "You do not have permission to share this collection" }, status: :forbidden)
      end

      collection
    elsif params[:asset_id].present?
      asset = Asset.find_by(id: params[:asset_id])
      return render(json: { error: "Asset not found" }, status: :not_found) if asset.nil?

      check_asset_modify!(asset)
      performed? ? nil : asset
    else
      render json: { error: "Either collection_id or asset_id is required" }, status: :unprocessable_entity
      nil
    end
  end

  # Replaces the portal's grants with exactly what was supplied.
  #
  # Declarative rather than incremental on purpose: the caller sends the set it
  # wants and anything absent is withdrawn. An "add these" endpoint makes
  # removal the thing you have to remember to do separately, and a permission
  # you forget to remove is the one that leaks.
  #
  # Grants are confined to the link's own target, so a portal over one
  # collection can never be pointed at an asset from another.
  def apply_grants!(portal, grants)
    entries = Array(grants).filter_map do |raw|
      entry = raw.respond_to?(:permit) ? raw.permit(:asset_id, :permission) : raw
      asset_id = entry[:asset_id] || entry["asset_id"]
      next if asset_id.blank?

      permission = (entry[:permission] || entry["permission"]).to_s
      permission = "view" unless PortalGrant::PERMISSIONS.include?(permission)
      [ asset_id.to_s, permission ]
    end

    # Only assets the link's target actually contains.
    allowed_ids = portal.target_assets.where(id: entries.map(&:first)).pluck(:id).map(&:to_s).to_set
    entries.select! { |(asset_id, _)| allowed_ids.include?(asset_id) }

    ReviewLink.transaction do
      portal.portal_grants.where.not(asset_id: entries.map(&:first)).delete_all
      entries.each do |(asset_id, permission)|
        grant = portal.portal_grants.find_or_initialize_by(asset_id: asset_id)
        grant.permission = permission
        grant.save!
      end
    end
  end

  def portal_params
    permitted = params.permit(:name, :expires_at, :require_email,
                              branding: [ :accent, :headline, :message, :logo_url ])
    permitted[:branding] = Portal::Branding.sanitise(permitted[:branding]) if permitted.key?(:branding)
    permitted
  end

  def portal_url_for(token:)
    Rails.application.routes.url_helpers.portal_url(
      token: token,
      host: request.host_with_port,
      protocol: request.protocol.delete_suffix("://"),
    )
  end

  # Never includes the token or its digest: the digest is a credential
  # equivalent for anyone who can reverse it and has no business leaving the
  # database.
  def serialize(portal, include_assets: false)
    grants = portal.portal_grants.to_a

    payload = {
      id: portal.id,
      name: portal.name,
      kind: portal.kind,
      status: status_for(portal),
      collection_id: portal.collection_id,
      asset_id: portal.asset_id,
      target_label: portal.target_label,
      branding: portal.branding_settings.to_h,
      expires_at: portal.expires_at,
      revoked_at: portal.revoked_at,
      require_email: portal.require_email?,
      passphrase_required: portal.passphrase_required?,
      access_count: portal.access_count,
      last_accessed_at: portal.last_accessed_at,
      granted_count: grants.size,
      downloadable_count: grants.count(&:download?),
      # What the partner can actually see once rights are applied. Shown
      # alongside granted_count so a portal with twelve picks and three
      # deliverable files is not silently misleading.
      distributable_count: portal.distributable_assets.count,
      download_count: portal.portal_downloads.count,
      created_at: portal.created_at,
      created_by: portal.created_by&.email,
    }

    payload[:assets] = serialize_target_assets(portal, grants) if include_assets
    payload
  end

  # Every asset in the target with its grant state, so the management UI can
  # render the whole pick list rather than only what is already granted.
  def serialize_target_assets(portal, grants)
    by_asset = grants.index_by { |g| g.asset_id.to_s }
    distributable = portal.target_assets.externally_distributable.license_current.pluck(:id).map(&:to_s).to_set

    portal.target_assets.order(created_at: :desc).map do |asset|
      grant = by_asset[asset.id.to_s]

      {
        id: asset.id,
        title: asset.title,
        usage_terms: asset.usage_terms,
        license_expires_at: asset.license_expires_at,
        permission: grant&.permission,
        granted: grant.present?,
        # False means a grant on this asset will not be honoured. Surfaced so
        # the sender finds out while configuring, not when the partner emails
        # to say a file is missing.
        externally_distributable: distributable.include?(asset.id.to_s),
      }
    end
  end

  def serialize_download(record)
    {
      id: record.id,
      asset_id: record.asset_id,
      asset_title: record.asset&.title,
      guest: record.review_guest&.display_name,
      guest_email: (record.review_guest&.anonymous? ? nil : record.review_guest&.email),
      ip_address: record.ip_address,
      downloaded_at: record.created_at,
    }
  end

  def status_for(portal)
    return "revoked" if portal.revoked?
    return "expired" if portal.expires_at.blank? || portal.expires_at.past?

    "active"
  end
end
