# A single utterance inside a {CommentThread}.
#
# A comment is always bound to the {AssetVersion} it was written against, so
# any attached {AnnotationTarget} geometry keeps its meaning even after newer
# versions are uploaded. The parent {CommentThread} is what survives across
# versions.
#
# Threading is intentionally **single-level**: a reply's parent is always a
# root comment. Arbitrarily deep nesting reads badly in a narrow review
# sidebar, and every reviewed product (Frame.io, Ziflow, Bynder) makes the
# same choice.
#
# Comments may be authored by a non-human agent — {AGENT_TYPES} includes
# +software+, mirroring the W3C Web Annotation Data Model's +Software+ agent
# class, so an AI review assistant can post suggestions that a human later
# promotes (at which point +author+ becomes the promoting human).
class Comment < ApplicationRecord
  include SoftDeletable

  # W3C Web Annotation Data Model motivations (§3.3.5) relevant to review.
  # +editing+ means "requests a change to the target" — i.e. a change request
  # rather than a passing remark.
  MOTIVATIONS = %w[commenting replying editing highlighting assessing questioning tagging].freeze

  AGENT_TYPES = %w[person software].freeze

  MAX_BODY_LENGTH = 10_000

  belongs_to :comment_thread
  belongs_to :asset_version, optional: true
  belongs_to :parent_comment, class_name: "Comment", optional: true
  belongs_to :author, class_name: "User", optional: true

  has_many :replies,
           -> { order(:created_at) },
           class_name: "Comment",
           foreign_key: :parent_comment_id,
           inverse_of: :parent_comment,
           dependent: :destroy

  has_many :annotation_targets, dependent: :destroy

  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }
  validates :motivation, inclusion: { in: MOTIVATIONS }
  validates :agent_type, inclusion: { in: AGENT_TYPES }
  validates :confidence,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
            allow_nil: true

  validate :human_comments_have_an_author
  validate :replies_are_single_level
  validate :reply_belongs_to_same_thread

  scope :roots, -> { where(parent_comment_id: nil) }
  scope :for_version, ->(version) { where(asset_version_id: version) }
  scope :by_software, -> { where(agent_type: "software") }
  scope :chronological, -> { order(:created_at) }

  delegate :asset, to: :comment_thread, allow_nil: true

  # @return [Boolean] true when the body has been changed since posting
  def edited?
    edited_at.present?
  end

  # @return [Boolean] true when this is a reply rather than a root comment
  def reply?
    parent_comment_id.present?
  end

  # @return [Boolean] true when this comment points at a region/moment of the media
  def annotated?
    annotation_targets.any?
  end

  # @return [String] display name for the author, human or machine
  def author_display_name
    return agent_name.presence || "Assistant" if agent_type == "software"

    author&.email.presence || "Unknown"
  end

  # Records an edit, stamping +edited_at+ so the UI can show "(edited)".
  #
  # @param new_body [String]
  # @return [Boolean]
  def edit!(new_body)
    update!(body: new_body, edited_at: Time.current)
  end

  private

  # A +person+ comment without an author would be unattributable, which
  # undermines the audit story. Software agents legitimately have no user.
  def human_comments_have_an_author
    return unless agent_type == "person"
    return if author_id.present?

    errors.add(:author, "must be present for a person-authored comment")
  end

  # Replies may not themselves be replied to — keeps the thread flat.
  def replies_are_single_level
    return if parent_comment.blank?
    return if parent_comment.parent_comment_id.blank?

    errors.add(:parent_comment, "cannot be a reply — threading is single-level")
  end

  def reply_belongs_to_same_thread
    return if parent_comment.blank?
    return if parent_comment.comment_thread_id == comment_thread_id

    errors.add(:parent_comment, "must belong to the same thread")
  end
end
