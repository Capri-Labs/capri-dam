# Shapes threads and comments for an *external* reviewer.
#
# WHY NOT REUSE {CommentSerialization} DIRECTLY
# ---------------------------------------------
# The internal serialiser emits +{ id:, email:, name: }+ for every author. Sent
# to a guest, that hands an outside party the email address and internal user
# id of everyone who has touched the review — a quiet but real disclosure, and
# a convenient list for a phishing campaign aimed at the client's agency.
#
# So identity is redacted here to a display name and nothing else. Geometry,
# by contrast, is reused verbatim: where a mark sits on the image is precisely
# what the guest is being shown.
#
# The rule this encodes: *the guest serialiser is an allow-list.* Adding a
# field to the internal representation must never silently widen what an
# external reviewer can see, which it would if this delegated wholesale.
module GuestReviewSerialization
  extend ActiveSupport::Concern
  include CommentSerialization

  private

  # @param thread [CommentThread]
  # @return [Hash]
  def serialize_guest_thread(thread)
    {
      id: thread.id,
      status: thread.status,
      closed: thread.closed?,
      # Deliberately no `visibility`: a guest only ever receives guest-visible
      # threads, so the field would carry no information and would advertise
      # that a hidden internal tier exists.
      origin_version: serialize_version_stub(thread.origin_version),
      author: guest_author_stub(user: thread.created_by, guest: thread.created_by_guest),
      comment_count: thread.comments.active.count,
      created_at: thread.created_at,
      comments: thread.comments.active.roots.chronological.map { |c| serialize_guest_comment(c) },
    }
  end

  # @param comment [Comment]
  # @param include_replies [Boolean]
  # @return [Hash]
  def serialize_guest_comment(comment, include_replies: true)
    payload = {
      id: comment.id,
      comment_thread_id: comment.comment_thread_id,
      parent_comment_id: comment.parent_comment_id,
      body: comment.body,
      motivation: comment.motivation,
      author: guest_author_stub(user: comment.author, guest: comment.review_guest, agent: comment),
      # Lets the guest app highlight the reviewer's own contributions without
      # having to compare identities client-side.
      mine: comment.review_guest_id.present? && comment.review_guest_id == current_review_guest&.id,
      edited: comment.edited?,
      created_at: comment.created_at,
      annotations: comment.annotation_targets.map { |a| serialize_annotation(a, thread_id: comment.comment_thread_id) },
    }

    payload[:replies] = comment.replies.active.map { |r| serialize_guest_comment(r, include_replies: false) } if include_replies

    payload
  end

  # Identity, reduced to what a guest legitimately needs: a name to attribute
  # the remark to, and whether it came from inside the organisation or from
  # their own side of the review.
  #
  # Never emits an email address or an internal user id.
  #
  # @return [Hash]
  def guest_author_stub(user: nil, guest: nil, agent: nil)
    if agent&.agent_type == "software"
      return { display_name: agent.agent_name.presence || "Assistant", kind: "software" }
    end

    if guest.present?
      return { display_name: guest.display_name, kind: "guest" }
    end

    if user.present?
      # Falls back to a generic label rather than the email when no name is
      # set, because the email is the thing being withheld.
      return { display_name: user.full_name.presence || "Capri team", kind: "team" }
    end

    { display_name: "Unknown", kind: "unknown" }
  end
end
