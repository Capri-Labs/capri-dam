module Comments
  # Builds the JSON body delivered by {CommentWebhookWorker}.
  #
  # WHY THIS IS NOT THE API SERIALISER
  # ----------------------------------
  # {CommentSerialization} shapes a response for a caller who has already
  # authenticated and already knows which asset they are looking at. A webhook
  # receiver has neither: it gets an unsolicited POST and must be able to route
  # it without a follow-up call. So the payload is deliberately *flatter and
  # more self-describing* — the asset and folder are named inline, and each
  # object carries an absolute URL a human can open.
  #
  # It is also deliberately *smaller*. A webhook is a notification, not a data
  # sync: it says what happened and where to look. Embedding the whole thread
  # tree would leak internal notes to an endpoint scoped to one asset and would
  # grow without bound on a long-running review.
  class WebhookPayload
    # @param event [String] one of {CommentWebhookSubscription::EVENTS}
    # @param record_id [String] Comment UUID for comment.* events,
    #   CommentThread UUID for thread.* events
    def initialize(event:, record_id:)
      @event = event
      @record_id = record_id
    end

    # @return [Hash, nil] nil when the record no longer exists
    def build
      comment_event? ? comment_payload : thread_payload
    end

    private

    attr_reader :event, :record_id

    def comment_event?
      event.start_with?("comment.")
    end

    def comment_payload
      comment = Comment.includes(:author, :annotation_targets, comment_thread: :asset).find_by(id: record_id)
      return nil if comment.blank? || comment.deleted_at.present?

      thread = comment.comment_thread
      return nil if thread.blank?

      envelope(thread.asset).merge(
        thread: thread_stub(thread),
        comment: comment_stub(comment),
      )
    end

    def thread_payload
      thread = CommentThread.includes(:asset, :created_by, :resolved_by).find_by(id: record_id)
      return nil if thread.blank?

      envelope(thread.asset).merge(thread: thread_stub(thread))
    end

    # Common to every event so a receiver can write one routing rule.
    def envelope(asset)
      {
        event: event,
        delivered_at: Time.current.iso8601,
        asset: asset_stub(asset),
      }
    end

    def asset_stub(asset)
      return nil if asset.blank?

      {
        id: asset.id,
        uuid: asset.try(:uuid),
        title: asset.title,
        status: asset.status,
        # Lives in the properties blob rather than a column — set by
        # AssetProcessorWorker during ingestion.
        content_type: asset.properties&.dig("content_type"),
        folder: asset.folder && { id: asset.folder.id, name: asset.folder.name },
        url: url("/assets/#{asset.id}"),
      }
    end

    def thread_stub(thread)
      {
        id: thread.id,
        status: thread.status,
        visibility: thread.visibility,
        closed: thread.closed?,
        comment_count: thread.comments.active.count,
        created_by: user_stub(thread.created_by),
        resolved_by: user_stub(thread.resolved_by),
        resolved_at: thread.resolved_at&.iso8601,
        created_at: thread.created_at&.iso8601,
        # The version the thread was raised against, which is what tells a
        # receiver whether the feedback is still about the current file.
        origin_version: thread.origin_version && {
          id: thread.origin_version.id,
          version_number: thread.origin_version.version_number,
        },
        url: url("/api/v1/comment_threads/#{thread.id}"),
      }
    end

    def comment_stub(comment)
      {
        id: comment.id,
        parent_comment_id: comment.parent_comment_id,
        body: comment.body,
        motivation: comment.motivation,
        agent_type: comment.agent_type,
        agent_name: comment.agent_name,
        author: user_stub(comment.author),
        author_display_name: comment.author_display_name,
        created_at: comment.created_at&.iso8601,
        # Geometry is summarised rather than reproduced: a receiver deciding
        # whether to act needs to know the feedback is anchored somewhere, not
        # its exact path data. The full W3C representation is one GET away.
        annotations: comment.annotation_targets.map { |t| annotation_stub(t) },
      }
    end

    def annotation_stub(target)
      {
        id: target.id,
        media_type: target.media_type,
        shape: target.shape,
        bbox: { x: target.bbox_x, y: target.bbox_y, w: target.bbox_w, h: target.bbox_h },
        start_frame: target.start_frame,
        end_frame: target.end_frame,
      }.compact
    end

    def user_stub(user)
      return nil if user.blank?

      { id: user.id, email: user.email, name: user.try(:full_name).presence || user.email }
    end

    def url(path)
      base = ENV["APP_BASE_URL"].presence ||
             Rails.application.config.action_mailer.default_url_options.to_h[:host]
      return path if base.blank?

      "#{base.to_s.chomp("/")}#{path}"
    end
  end
end
