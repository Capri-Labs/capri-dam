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

  belongs_to :asset
  belongs_to :origin_version, class_name: "AssetVersion", optional: true
  belongs_to :created_by, class_name: "User"
  belongs_to :resolved_by, class_name: "User", optional: true

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

  # Threads still awaiting action.
  scope :unresolved, -> { where(status: OPEN_STATUSES) }

  # Threads that have at least one comment written against a given version.
  # @param version [AssetVersion, String] the version or its UUID
  scope :for_version, ->(version) {
    joins(:comments).where(comments: { asset_version_id: version, deleted_at: nil }).distinct
  }

  scope :visible_to_guests, -> { where(visibility: "guest") }

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
end
