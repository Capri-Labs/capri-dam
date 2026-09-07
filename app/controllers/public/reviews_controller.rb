module Public
  # The guest review surface: what someone holding a {ReviewLink} sees and can
  # do without a Capri account.
  #
  # Authenticated entirely by {ReviewLinkAuthentication} — there is no Devise
  # session, no OAuth token and no folder policy anywhere in this request. See
  # that concern for why the guest path deliberately shares no authorisation
  # code with the internal comment endpoints.
  class ReviewsController < ApplicationController
    include ReviewLinkAuthentication
    include GuestReviewSerialization

    layout "public_review"

    # Devise's CSRF protection is session-based and the guest app posts JSON
    # with the token from the page's meta tag, exactly like the internal SPA,
    # so forgery protection stays on.

    # An unauthenticated endpoint reachable by anyone with a URL is a
    # brute-force and spam surface. Rails 8's built-in limiter is used rather
    # than adding a dependency.
    rate_limit to: 60, within: 1.minute, only: %i[show assets threads]
    rate_limit to: 10, within: 1.minute, only: %i[identify],
               with: -> { render json: { error: "Too many attempts. Please wait a moment." }, status: :too_many_requests }
    rate_limit to: 10, within: 1.minute, only: %i[unlock],
               with: -> { render json: { error: "Too many attempts. Please wait a moment." }, status: :too_many_requests }

    # The passphrase gate has to be reachable *before* the gate is satisfied,
    # so it opts out of the normal check and validates the token itself.
    skip_before_action :set_review_link, only: %i[unlock]

    # GET /s/reviews/:token
    #
    # The HTML shell. Everything else on this controller is JSON consumed by
    # the guest review app mounted here.
    def show
      @assets = @review_link.scoped_assets.order(created_at: :desc)
      @guest  = current_review_guest
    end

    # GET /s/reviews/:token/assets
    def assets
      render json: {
        review: review_stub,
        guest: guest_stub(current_review_guest),
        assets: @review_link.scoped_assets.order(created_at: :desc).map { |a| asset_stub(a) },
      }
    end

    # POST /s/reviews/:token/identify
    #
    # Captures who the reviewer is. This is attribution, not authentication —
    # see {ReviewGuest} — so it deliberately does not verify the address or
    # look for a matching {User}.
    def identify
      guest = ReviewGuest.identify!(
        review_link: @review_link,
        email: params[:email],
        name: params[:name],
      )
      remember_review_guest(guest)

      render json: { guest: guest_stub(guest) }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    # POST /s/reviews/:token/unlock
    #
    # Exchanges a passphrase for session access to a protected link.
    def unlock
      link = ReviewLink.find_by_token(params[:token])
      return render(json: { error: "This review link is not valid." }, status: :gone) if link.nil? || !link.usable?

      @review_link = link
      unless link.passphrase_matches?(params[:passphrase])
        return render json: { error: "That passphrase is not correct." }, status: :unauthorized
      end

      mark_passphrase_cleared!
      render json: { ok: true }
    end

    # GET /s/reviews/:token/assets/:asset_id/threads
    def threads
      asset = scoped_asset(params[:asset_id])
      return render(json: { error: "Not found" }, status: :not_found) if asset.nil?

      threads = guest_visible_threads(asset)
                .includes(:origin_version, :created_by, :created_by_guest,
                          comments: [ :author, :review_guest, :asset_version, :annotation_targets ])
                .order(created_at: :asc)

      render json: {
        threads: threads.map { |t| serialize_guest_thread(t) },
        can_comment: can_comment?,
        meta: { total: threads.size },
      }
    end

    private

    def review_stub
      {
        name: @review_link.name,
        target_label: @review_link.target_label,
        expires_at: @review_link.expires_at,
        allow_comments: @review_link.allow_comments,
        allow_downloads: @review_link.allow_downloads,
        require_email: @review_link.require_email,
        identified: review_guest_identified?,
      }
    end

    def guest_stub(guest)
      return nil if guest.blank?

      { id: guest.id, email: guest.email, name: guest.name, display_name: guest.display_name }
    end

    def asset_stub(asset)
      {
        id: asset.id,
        title: asset.title,
        content_type: asset.properties&.dig("content_type"),
        # Streamed through the guest proxy, never as a direct storage URL: a
        # signed CDN link would outlive the review link's revocation.
        preview_url: review_preview_asset_path(token: params[:token], asset_id: asset.id),
        downloadable: @review_link.allow_downloads?,
      }
    end
  end
end
