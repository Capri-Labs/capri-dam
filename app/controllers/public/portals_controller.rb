module Public
  # The **distribution portal**: a branded, unauthenticated surface where an
  # external partner collects the specific files they were given, and nothing
  # else.
  #
  # HOW THIS DIFFERS FROM THE REVIEW SURFACE
  # ----------------------------------------
  # A review link shares a whole target so somebody can comment on it. A portal
  # shares a hand-picked subset so somebody can *take* it. The credential
  # machinery is identical and deliberately shared (see
  # {ReviewLinkAuthentication}); what differs is that every asset here has to
  # clear an explicit {PortalGrant}, and that taking a file is recorded.
  #
  # THREE INDEPENDENT GATES
  # -----------------------
  # An asset is only visible if it is *still in the collection*, *explicitly
  # granted*, and *cleared for external release* by {Rights::DownloadPolicy}.
  # They are independent on purpose: revoking any one of them withdraws the
  # asset without anybody having to remember the other two.
  class PortalsController < ApplicationController
    include ReviewLinkAuthentication
    include AssetUrlHelper

    # Portal tokens only. A review token routed here would arrive with no
    # grants at all, and the collection-wide scope it carries is exactly what
    # grants exist to narrow.
    serves_link_kind :portal

    layout "public_portal"

    # Unlocking must be reachable before the passphrase is satisfied, so it
    # resolves and validates the token itself.
    skip_before_action :set_review_link, :enforce_link_kind, only: %i[unlock]

    rate_limit to: 10, within: 1.minute, only: %i[unlock],
               with: -> { render json: { error: "Too many attempts. Please wait a moment." }, status: :too_many_requests }
    rate_limit to: 20, within: 1.minute, only: %i[identify],
               with: -> { render json: { error: "Too many attempts. Please wait a moment." }, status: :too_many_requests }

    # GET /s/portal/:token
    def show
      @branding = @review_link.branding_settings
      @guest    = current_review_guest
    end

    # GET /s/portal/:token/assets
    def assets
      render json: {
        portal: portal_stub,
        guest: guest_stub(current_review_guest),
        assets: visible_assets.map { |a| asset_stub(a) },
      }
    end

    # POST /s/portal/:token/identify
    #
    # Attribution, not authentication — the address is self-asserted. It exists
    # so a download log reads "Priya at the agency" rather than an IP.
    def identify
      guest = ReviewGuest.identify!(review_link: @review_link, email: params[:email], name: params[:name])
      remember_review_guest(guest)

      render json: { guest: guest_stub(guest) }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    # POST /s/portal/:token/unlock
    def unlock
      link = ReviewLink.find_by_token(params[:token])
      if link.nil? || !link.usable? || link.kind != self.class.served_link_kind
        return render(json: { error: "This share link is not valid." }, status: :gone)
      end

      @review_link = link
      unless link.passphrase_matches?(params[:passphrase])
        return render json: { error: "That passphrase is not correct." }, status: :unauthorized
      end

      mark_passphrase_cleared!
      render json: { ok: true }
    end

    private

    # The assets this guest may see: granted, still in the collection, and
    # cleared to leave the organisation.
    def visible_assets
      @review_link.distributable_assets.order(created_at: :desc)
    end

    def portal_stub
      branding = @review_link.branding_settings

      {
        name: @review_link.name,
        headline: branding.headline || @review_link.name,
        message: branding.message,
        accent: branding.accent,
        logo_url: branding.logo_url,
        expires_at: @review_link.expires_at,
        require_email: @review_link.require_email?,
        identified: review_guest_identified?,
      }
    end

    def guest_stub(guest)
      return nil if guest.nil?

      { id: guest.id, name: guest.display_name, anonymous: guest.anonymous? }
    end

    # Deliberately narrow. A portal is a pick-up point, not a catalogue: the
    # partner needs to recognise the file, know how big it is and know whether
    # they may take it. Internal metadata, folder placement, versions and
    # comment threads are not part of that and are not sent.
    def asset_stub(asset)
      downloadable = @review_link.may_download?(asset)

      {
        id: asset.id,
        title: asset.title,
        content_type: asset_property(asset, "content_type"),
        byte_size: asset_property(asset, "file_size"),
        preview_url: portal_asset_preview_path(token: params[:token], asset_id: asset.id),
        downloadable: downloadable,
        # Absent rather than present-and-forbidden: a link the guest cannot use
        # should not be rendered as a button they can press.
        download_url: (downloadable ? portal_asset_download_path(token: params[:token], asset_id: asset.id) : nil),
      }
    end

    # Reads a property from the active version first and the asset second, the
    # same resolution order the storage paths use.
    def asset_property(asset, key)
      version_props = asset.active_version&.properties
      value = version_props.is_a?(Hash) ? version_props[key] : nil
      return value if value.present?

      asset.properties.is_a?(Hash) ? asset.properties[key] : nil
    end
  end
end
