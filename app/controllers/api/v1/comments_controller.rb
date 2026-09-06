module Api
  module V1
    # Individual comments inside a {CommentThread} — replies, edits and
    # deletions. Thread-level operations (listing, opening a new thread,
    # resolving) live in {Api::V1::CommentThreadsController}.
    #
    # PERMISSIONS
    # -----------
    # Posting a reply needs only +:read+ on the asset's folder, for the same
    # reason opening a thread does: reviewing is not editing. Editing or
    # deleting a comment is restricted to its **author** — moderation of other
    # people's words is deliberately not offered here, because an audit trail
    # that anyone with +:modify+ can rewrite is not an audit trail. Removing an
    # entire thread (which an asset manager may legitimately need) is available
    # on the thread endpoint instead.
    class CommentsController < ApplicationController
      include CommentSerialization

      before_action :authenticate_hybrid!
      before_action :require_write_scope!
      before_action :set_thread,  only: %i[create]
      before_action :set_comment, only: %i[update destroy]

      # POST /api/v1/comment_threads/:comment_thread_id/comments
      #
      #   {
      #     "body": "Fixed in this version",
      #     "parent_comment_id": "…",      # optional — makes it a reply
      #     "asset_version_id": "…",       # defaults to the asset's active version
      #     "annotations": [ … ]
      #   }
      #
      # Posting on a newer version than the thread started on is the normal way
      # to say "this is handled now", so the caller may also move the thread to
      # +addressed+ via +mark_addressed+.
      def create
        version = resolve_version(params[:asset_version_id]) || @thread.asset.active_version

        comment = nil
        ActiveRecord::Base.transaction do
          comment = @thread.comments.create!(
            body: params.require(:body),
            author: current_user,
            asset_version: version,
            parent_comment: resolve_parent(params[:parent_comment_id]),
            motivation: params[:motivation].presence || (params[:parent_comment_id].present? ? "replying" : "commenting"),
          )

          Array(params[:annotations]).each do |raw|
            comment.annotation_targets.create!(annotation_attributes_from(raw))
          end

          # Claiming the feedback is handled is an explicit act, never inferred
          # from the mere existence of a newer comment.
          @thread.update!(status: "addressed") if truthy?(params[:mark_addressed]) && !@thread.closed?
        end

        CommentNotificationService.new(comment).deliver

        render json: serialize_comment(comment), status: :created
      rescue ActionController::ParameterMissing => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      # PATCH /api/v1/comments/:id
      # Stamps +edited_at+ so the UI can mark the comment "(edited)" rather than
      # letting history be rewritten invisibly.
      def update
        return unless author_only!

        if @comment.edit!(params.require(:body))
          render json: serialize_comment(@comment)
        else
          render json: { error: @comment.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end
      rescue ActionController::ParameterMissing => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      # DELETE /api/v1/comments/:id
      # Soft delete — the row stays for audit and the UI renders a tombstone.
      def destroy
        return unless author_only!

        @comment.soft_delete
        head :no_content
      end

      private

      def set_thread
        @thread = CommentThread.active.includes(:asset).find(params[:comment_thread_id])
        check_asset_read!(@thread.asset)
      end

      def set_comment
        @comment = Comment.active.includes(comment_thread: :asset).find(params[:id])
        check_asset_read!(@comment.comment_thread.asset)
      end

      # @return [Boolean] false when a 403 has already been rendered
      def author_only!
        return true if @comment.author_id.present? && @comment.author_id == current_user&.id

        render json: { error: "You can only modify your own comments." }, status: :forbidden
        false
      end

      def resolve_version(version_id)
        return nil if version_id.blank?

        @thread.asset.asset_versions.find_by(id: version_id)
      end

      # A reply must point at a comment in *this* thread. Silently falling back
      # to nil would turn a typo'd or cross-thread id into a new root comment,
      # quietly detaching the reply from the conversation it answered.
      def resolve_parent(parent_id)
        return nil if parent_id.blank?

        @thread.comments.active.find(parent_id)
      end

      def truthy?(value)
        ActiveModel::Type::Boolean.new.cast(value).present?
      end
    end
  end
end
