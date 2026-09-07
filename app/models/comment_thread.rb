# A conversation about an {Asset}.
#
# Deliberately **version-independent**: the thread belongs to the asset, while
# each individual {Comment} inside it records the {AssetVersion} it was written
# against. That split is what lets feedback outlive a re-upload.
#
# Every comparable product (Frame.io, Ziflow, Bynder, Acquia DAM) binds a
# comment to exactly one version and orphans it when the next version lands.
# Keeping the thread on the asset gives the conversation a lifecycle that
# spans versions:
#
#   open  --(a newer version claims to fix it)-->  addressed
#         --(the original reviewer confirms)---->  verified
#         --(closed, no further action needed)-->  resolved
#
# @example Start a thread with the first comment
#   thread = CommentThread.create!(asset: asset, created_by: user,
#                                  origin_version: asset.active_version)
#   thread.comments.create!(body: "The logo is too small", author: user,
#                           asset_version: asset.active_version)
class CommentThread < ApplicationRecord
  include SoftDeletable

  # Lifecycle states. `addressed` and `verified` are the two halves of the
  # cross-version review loop — a designer marks feedback addressed on a new
  # version, the reviewer verifies it.
  STATUSES = %w[open addressed verified resolved].freeze

  # `internal` threads are visible to anyone with folder :read.
  # `guest` threads are additionally exposed to external share-link reviewers.
  # Modelling this as a first-class flag (rather than fudging it with
  # permissions) means an internal note can never leak to a client by accident.
  VISIBILITIES = %w[internal guest].freeze

  # Statuses that still require someone to act.
  OPEN_STATUSES = %w[open addressed].freeze

  # Triage state for a thread the AI review assistant opened. NULL for every
  # human-authored thread — the column answers "has a person decided about
  # this machine suggestion yet?", a question that simply does not apply to a
  # remark a person wrote themselves.
  #
  # A pending suggestion is deliberately *not* part of the review yet. It is
  # stored as a real thread (so it keeps annotation geometry, version binding
  # and region-diff) but is filtered out of every human and guest listing until
  # somebody accepts it. Machine output must never silently become a client's
  # feedback.
  SUGGESTION_STATES = %w[pending accepted dismissed].freeze

  belongs_to :asset
  belongs_to :origin_version, class_name: "AssetVersion", optional: true
  # Optional because a thread may have been opened by an external reviewer
  # holding a {ReviewLink} rather than by an account holder. Exactly one of
  # +created_by+ and +created_by_guest+ is always set, enforced by the
  # +comment_threads_have_an_author+ check constraint.
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :created_by_guest, class_name: "ReviewGuest", optional: true
  # Which link an external thread arrived through, so a revoked link's
  # contributions remain traceable after the fact.
  belongs_to :review_link, optional: true
  belongs_to :resolved_by, class_name: "User", optional: true
  # Present when the assistant opened this thread. Also what satisfies the
  # +comment_threads_have_an_author+ constraint for machine-authored threads.
  belongs_to :ai_review, optional: true
  belongs_to :suggestion_decided_by, class_name: "User", optional: true

  has_many :comments, dependent: :destroy

  # Top-level comments only — replies hang off their parent.
  has_many :root_comments,
           -> { where(parent_comment_id: nil).order(:created_at) },
           class_name: "Comment",
           inverse_of: :comment_thread,
           dependent: nil

  has_many :annotation_targets, through: :comments

  validates :status, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :suggestion_state, inclusion: { in: SUGGESTION_STATES }, allow_nil: true
  validate :has_an_author
  validate :suggestion_state_belongs_to_a_review

  # Threads still awaiting action.
  scope :unresolved, -> { where(status: OPEN_STATUSES) }

  # Threads that have at least one comment written against a given version.
  # @param version [AssetVersion, String] the version or its UUID
  scope :for_version, ->(version) {
    joins(:comments).where(comments: { asset_version_id: version, deleted_at: nil }).distinct
  }

  scope :visible_to_guests, -> { where(visibility: "guest") }

  # Threads that count as part of the review: everything a human wrote, plus
  # machine suggestions somebody has accepted.
  #
  # This is the scope every listing must use.
  #
  # +IS DISTINCT FROM+ rather than +where.not+: human threads have a NULL
  # +suggestion_state+, and `suggestion_state != 'pending'` evaluates to NULL
  # for those rows, which SQL treats as not-matched. A plain +where.not+ here
  # would therefore hide every human-authored thread in the system.
  scope :triaged, -> { where("suggestion_state IS DISTINCT FROM 'pending'") }

  # Untriaged machine output, awaiting a human decision.
  scope :pending_suggestions, -> { where(suggestion_state: "pending") }

  scope :suggested_by_ai, -> { where.not(ai_review_id: nil) }

  # @return [String] who opened the thread, for display
  def creator_display_name
    return ai_review_display_name if ai_suggested?

    created_by&.email.presence || created_by_guest&.display_name || "Unknown"
  end

  # @return [Boolean] whether the assistant opened this thread
  def ai_suggested?
    ai_review_id.present?
  end

  # @return [Boolean] whether this is machine output nobody has ruled on yet
  def pending_suggestion?
    suggestion_state == "pending"
  end

  # Folds a machine suggestion into the human review.
  #
  # The accepting user is recorded as the decision-maker but is deliberately
  # *not* rewritten as the comment's author: the assistant did write it, and
  # laundering machine output into a person's name would destroy the audit
  # trail that {Comment#agent_type} exists to keep. Attribution stays with the
  # machine; accountability for admitting it attaches to the human.
  #
  # @param user [User] who accepted it
  # @return [Boolean]
  def accept_suggestion!(user:)
    raise ArgumentError, "not a pending suggestion" unless pending_suggestion?

    update!(
      suggestion_state: "accepted",
      suggestion_decided_by: user,
      suggestion_decided_at: Time.current,
    )
  end

  # Rejects a machine suggestion.
  #
  # Dismissed suggestions are kept rather than deleted: what the assistant got
  # wrong is the only evidence available for tuning it, and a silently deleted
  # false positive will simply be raised again on the next run.
  #
  # @param user [User] who dismissed it
  # @return [Boolean]
  def dismiss_suggestion!(user:)
    raise ArgumentError, "not a pending suggestion" unless pending_suggestion?

    update!(
      suggestion_state: "dismissed",
      suggestion_decided_by: user,
      suggestion_decided_at: Time.current,
    )
  end

  # @return [Boolean] whether this thread originated outside the organisation
  def guest_originated?
    created_by_guest_id.present?
  end

  # Marks the thread closed.
  #
  # @param user [User] who is closing it
  # @param status [String] +"resolved"+ (closed) or +"verified"+ (fix confirmed)
  # @return [Boolean]
  def resolve!(user:, status: "resolved")
    raise ArgumentError, "unsupported resolve status: #{status}" unless %w[resolved verified].include?(status)

    update!(status: status, resolved_at: Time.current, resolved_by: user)
  end

  # Reopens a previously closed thread, clearing the resolution attribution.
  # @return [Boolean]
  def reopen!
    update!(status: "open", resolved_at: nil, resolved_by: nil)
  end

  # @return [Boolean] true when nobody needs to act on this thread any more
  def closed?
    !OPEN_STATUSES.include?(status)
  end

  # The most recent version any comment in this thread was written against.
  # Used by the UI to show "last discussed on v3".
  #
  # @return [AssetVersion, nil]
  def latest_commented_version
    comments.active.includes(:asset_version).filter_map(&:asset_version).max_by(&:version_number)
  end

  # Everyone who has spoken in the thread — the natural notification audience
  # for a new reply.
  #
  # @return [Array<User>]
  def participants
    User.where(id: comments.active.where.not(author_id: nil).select(:author_id).distinct)
  end

  private

  # Mirrors the +comment_threads_have_an_author+ check constraint so the
  # failure surfaces as a validation error rather than a database exception.
  # A recorded assistant run counts as an author: the thread is attributable
  # to a specific {AiReview}, which names the model that produced it.
  def has_an_author
    return if created_by_id.present? || created_by_guest_id.present? || ai_review_id.present?

    errors.add(:base, "A thread must be opened by a user, a review guest, or an AI review")
  end

  # Triage state is meaningless without something to triage. Allowing it on a
  # human thread would let a person's remark be "dismissed" through the
  # suggestion path, bypassing the resolve/reopen lifecycle entirely.
  def suggestion_state_belongs_to_a_review
    return if suggestion_state.blank?
    return if ai_review_id.present?

    errors.add(:suggestion_state, "only applies to a thread opened by an AI review")
  end

  def ai_review_display_name
    name = ai_review&.ai_model_name.presence
    name ? "Review assistant (#{name})" : "Review assistant"
  end
end
