# Authenticates a request purely on the strength of a {ReviewLink} token.
#
# THIS IS A SEPARATE AUTHENTICATION SYSTEM, ON PURPOSE
# ----------------------------------------------------
# Nothing here touches Devise, Doorkeeper, +current_user+ or the folder policy
# engine. The internal comment endpoints and the guest endpoints share
# serialisation but never share an authorisation path, so there is no branch
# anywhere of the form "if the guest flag is set, skip the permission check" —
# which is exactly the shape of bug that turns a review link into a data
# breach. A guest controller cannot accidentally inherit an internal
# permission, because it never had one to begin with.
#
# WHAT THE TOKEN GRANTS
# ---------------------
# Sight of the assets in {ReviewLink#scoped_assets}, the *guest-visible*
# threads on them, and — if the link allows it — the ability to add comments.
# Never anything else: not other assets, not internal threads, not resolution,
# not the authenticated API.
module ReviewLinkAuthentication
  extend ActiveSupport::Concern

  included do
    # Which kind of link this surface serves. Nil means "either", which no
    # controller should choose deliberately.
    class_attribute :served_link_kind, instance_writer: false, default: nil

    # These pages are a credential in a URL. Search engines must never index
    # them, and neither should an intermediary cache hold a copy.
    before_action :set_review_link
    before_action :enforce_link_kind
    before_action :discourage_caching
  end

  class_methods do
    # Declares that this controller serves one kind of link only.
    #
    # Without this, a portal token would be accepted by the review surface and
    # a review token by the portal surface — and each surface applies the
    # permission model of the *route*, not of the link. A review link routed
    # through the portal would hand out every asset in the collection with no
    # grants to narrow it; a portal link routed through review would offer
    # commenting that was never granted. The kinds diverge in what they permit,
    # so they must not be interchangeable in the URL.
    #
    # @param kind [String, Symbol]
    def serves_link_kind(kind)
      self.served_link_kind = kind.to_s
    end
  end

  private

  # @return [ReviewLink, nil]
  attr_reader :review_link

  def set_review_link
    @review_link = ReviewLink.find_by_token(params[:token])

    # A token that resolves to nothing is simply invalid. There is no
    # information leak in distinguishing this from the cases below: reaching
    # any of them requires already holding a real 32-byte token, which cannot
    # be guessed.
    return deny(:not_found) if @review_link.nil?

    if (reason = @review_link.unusable_reason)
      # Saying *why* it stopped working is useful — "expired" and "withdrawn"
      # prompt different conversations — and is only ever shown to someone who
      # legitimately held the link.
      return deny(reason)
    end

    return deny(:passphrase_required) unless passphrase_cleared?

    @review_link.record_access!
  end

  # A link of the wrong kind is reported as simply not found: the holder of a
  # valid review token learns nothing about whether a portal exists at the
  # same address, and there is no legitimate flow that lands here.
  def enforce_link_kind
    return if performed?
    return if served_link_kind.blank?
    return if @review_link&.kind == served_link_kind

    deny(:not_found)
  end

  # The passphrase is checked once and remembered in the session, so a guest
  # is not asked again on every fetch the review page makes.
  def passphrase_cleared?
    return true unless @review_link.passphrase_required?

    Array(session[:cleared_review_links]).include?(@review_link.id)
  end

  def mark_passphrase_cleared!
    session[:cleared_review_links] = (Array(session[:cleared_review_links]) + [ @review_link.id ]).uniq
  end

  # The guest identity established for this link in this session, if any.
  #
  # @return [ReviewGuest, nil]
  def current_review_guest
    return @current_review_guest if defined?(@current_review_guest)

    guest_id = session.dig("review_guests", @review_link&.id)
    # Scoped to the link: a session that identified on one link must not carry
    # that identity onto a different one.
    @current_review_guest = guest_id && @review_link&.review_guests&.find_by(id: guest_id)
  end

  # The identity to attribute a write to.
  #
  # When a link does not demand an email, the reviewer is still a distinct
  # person whose comments have to be told apart from the next reviewer's — so
  # an anonymous identity is minted for the session rather than leaving the
  # comment unattributed. Anonymous reviewers are kept separate from one
  # another instead of being collapsed into one shared "Guest" persona, which
  # would misrepresent two people's disagreement as one person contradicting
  # themselves.
  #
  # @return [ReviewGuest]
  def review_guest_for_write!
    current_review_guest || remember_review_guest(ReviewGuest.anonymous!(review_link: @review_link))
  end

  # @param guest [ReviewGuest]
  def remember_review_guest(guest)
    session["review_guests"] = (session["review_guests"] || {}).merge(@review_link.id => guest.id)
    @current_review_guest = guest
  end

  # @return [Boolean]
  def review_guest_identified?
    current_review_guest.present?
  end

  # Whether this link permits writing at all, and whether we know who is
  # writing when the link demands it.
  def can_comment?
    return false unless @review_link.allow_comments?
    return true unless @review_link.require_email?

    review_guest_identified?
  end

  # Resolves an asset *within the link's scope*.
  #
  # Always goes through {ReviewLink#covers?} rather than a bare +Asset.find+,
  # so a guest cannot pivot to an unrelated asset by editing the id in the URL.
  #
  # @return [Asset, nil]
  def scoped_asset(asset_id)
    return nil if asset_id.blank?

    @review_link.distributable_assets.find_by(id: asset_id)
  end

  # Threads a guest is allowed to see on an asset: guest-visible only.
  #
  # Internal threads are excluded here, at the source, rather than being
  # fetched and filtered later — so a future change to the serialiser cannot
  # accidentally start emitting them.
  #
  # @param asset [Asset]
  # @return [ActiveRecord::Relation<CommentThread>]
  def guest_visible_threads(asset)
    # +triaged+ is belt-and-braces: assistant threads are created +internal+
    # so +visible_to_guests+ already excludes them. It is repeated here because
    # the cost of the redundancy is nothing and the cost of a machine's
    # unreviewed guess reaching a client is a great deal.
    asset.comment_threads.active.visible_to_guests.triaged
  end

  def discourage_caching
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    response.headers["Cache-Control"] = "no-store"
  end

  # Renders the refusal, in whichever format was asked for.
  #
  # @param reason [Symbol]
  def deny(reason)
    @denial_reason = reason
    status = reason == :passphrase_required ? :unauthorized : :gone

    respond_to do |format|
      format.html { render "public/reviews/unavailable", status: status, layout: denial_layout }
      format.json { render json: { error: denial_message(reason), reason: reason }, status: status }
      format.any  { head status }
    end
  end

  # The refusal is rendered in the chrome of the surface that was asked for,
  # so a partner who follows a dead portal link is not suddenly looking at a
  # page about reviews.
  def denial_layout
    served_link_kind == "portal" ? "public_portal" : "public_review"
  end

  # Worded for the surface, not the table. "Review link" is the internal name
  # for both kinds; a partner collecting artwork has never heard it.
  def denial_message(reason)
    noun = served_link_kind == "portal" ? "share link" : "review link"

    case reason
    when :not_found           then "This #{noun} is not valid."
    when :expired             then "This #{noun} has expired."
    when :revoked             then "This #{noun} has been withdrawn."
    when :passphrase_required then "This #{noun} requires a passphrase."
    else "This #{noun} is unavailable."
    end
  end
end
