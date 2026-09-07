module Comments
  # Fans a review event out to every subscribed endpoint.
  #
  # WHY A PUBLISHER RATHER THAN CALLING THE WORKER DIRECTLY
  # ------------------------------------------------------
  # The controllers should not know how many endpoints exist, how they are
  # scoped, or that dispatch is asynchronous at all. They know only that
  # something happened. Concentrating the fan-out here also means a new event
  # source (the importer, the workflow engine, a future guest-review link) gets
  # correct scoping for free.
  #
  # PUBLISHING MUST NEVER BREAK THE ACTION THAT CAUSED IT
  # ----------------------------------------------------
  # Posting a comment is the user's work; notifying an integration is a side
  # effect. A misconfigured subscription, an unreachable Redis, or a bug in
  # payload construction must not turn a successful comment into a 500. Every
  # failure here is logged and swallowed.
  class EventPublisher
    class << self
      # @param comment [Comment]
      # @return [Integer] number of deliveries enqueued
      def comment_created(comment)
        publish("comment.created", comment&.id, comment&.comment_thread&.asset)
      end

      # @param comment [Comment]
      def comment_resolved(comment)
        publish("comment.resolved", comment&.id, comment&.comment_thread&.asset)
      end

      # @param thread [CommentThread]
      def thread_created(thread)
        publish("thread.created", thread&.id, thread&.asset)
      end

      # @param thread [CommentThread]
      def thread_resolved(thread)
        publish("thread.resolved", thread&.id, thread&.asset)
      end

      # @param thread [CommentThread]
      def thread_reopened(thread)
        publish("thread.reopened", thread&.id, thread&.asset)
      end

      private

      def publish(event, record_id, asset)
        return 0 if record_id.blank? || asset.blank?

        subscriptions = CommentWebhookSubscription.listening_for(event, asset)
        subscriptions.each do |subscription|
          CommentWebhookWorker.perform_async(event, record_id.to_s, subscription.id)
        end
        subscriptions.size
      rescue StandardError => e
        # Deliberately broad: see the class note. Nothing an integration does
        # may cost the user their comment.
        Rails.logger.error("[Comments::EventPublisher] #{event} for #{record_id} failed to publish: #{e.message}")
        0
      end
    end
  end
end
