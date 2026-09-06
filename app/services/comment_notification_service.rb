# Fans a new {Comment} out to everyone who should hear about it.
#
# Three distinct audiences, deliberately kept separate so nobody is notified
# twice for the same comment:
#
#   1. **Mentioned users** — anyone named with +@handle+ in the body. Handled by
#      the existing {InboxDeliveryService.deliver_mention}, which already
#      resolves handles, writes an {InboxMessage} and triggers the
#      +user_mentioned+ email template.
#   2. **Thread participants** — anyone who previously spoke in the thread, plus
#      the thread's author. They get a lighter "new reply" notification.
#   3. **Nobody else.** Asset owners are intentionally *not* blanket-notified;
#      commenting would become a spam vector on busy libraries.
#
# Email is routed through {EmailOrchestrator} using the event triggers
# registered in +Admin::EmailTemplatesController::SYSTEM_EVENTS+, so an
# administrator can rewrite the copy without a deploy. If no template is
# active for an event the orchestrator simply no-ops — in-app delivery still
# happens.
class CommentNotificationService
  # @param comment [Comment, nil] tolerates nil so callers need no guard
  def initialize(comment)
    @comment = comment
  end

  # Notifies mentioned users and thread participants about a new comment.
  # @return [void]
  def deliver
    return if comment.blank?

    notify_mentions
    notify_participants
  end

  # Tells the thread's original author that their feedback was closed.
  #
  # @param by [User] whoever resolved or verified the thread
  # @return [void]
  def deliver_resolution(by:)
    return if comment.blank?

    author = thread.created_by
    return if author.blank? || author == by

    Notification.create!(
      user: author,
      title: "Comment #{thread.status} on #{asset.title}",
      message: "#{by.full_name} marked your comment #{thread.status}.",
      action_url: context_url
    )

    EmailOrchestrator.trigger("comment_resolved", author.email, email_payload(actor: by))
  end

  private

  attr_reader :comment

  def thread
    comment.comment_thread
  end

  def asset
    thread.asset
  end

  # Reuses the product's existing mention pipeline verbatim — it already
  # accepts a polymorphic reference, and +inbox_messages.reference_id+ is
  # already a uuid column, so a Comment slots in with no schema change.
  def notify_mentions
    return if comment.author.blank?

    MentionProcessorWorker.perform_async(
      comment.body,
      comment.author_id,
      context_url,
      "Comment",
      comment.id
    )
  end

  def notify_participants
    recipients = (thread.participants.to_a + [ thread.created_by ]).compact.uniq
    recipients -= [ comment.author ]
    recipients -= mentioned_users # already told, via a richer message

    recipients.each do |recipient|
      Notification.create!(
        user: recipient,
        title: "New comment on #{asset.title}",
        message: "#{comment.author_display_name}: #{comment.body.to_s.truncate(120)}",
        action_url: context_url
      )

      EmailOrchestrator.trigger("comment_created", recipient.email, email_payload(actor: comment.author))
    end
  end

  def mentioned_users
    @mentioned_users ||= MentionDetectionService.extract_mentions(comment.body.to_s)
                                                .filter_map { |m| m[:user] }
  rescue StandardError
    # A malformed handle must never prevent the comment itself from notifying.
    []
  end

  # Deep-links straight to the asset so the recipient lands on the thread.
  # `/assets?id=UUID` is the Explorer's documented deep-link form (see
  # `config/routes.rb` and `AssetExplorer#readUrlFilters`, which reads `id`);
  # `thread` is carried alongside so the viewer can preselect the conversation.
  def context_url
    base = ENV.fetch("APP_HOST", nil).presence
    path = "/assets?id=#{asset.uuid || asset.id}&thread=#{thread.id}"
    base.present? ? "#{base.chomp("/")}#{path}" : path
  end

  def email_payload(actor:)
    {
      "comment" => {
        "body" => comment.body.to_s.truncate(500),
        "author" => actor.respond_to?(:full_name) ? actor.full_name : comment.author_display_name,
        "status" => thread.status,
      },
      "asset" => {
        "name" => asset.title,
        "url" => context_url,
      },
      "context" => {
        "name" => asset.title,
        "url" => context_url,
      },
    }
  end
end
