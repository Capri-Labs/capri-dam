module Api
  module V1
    # Review conversations about an asset — the general-purpose commenting and
    # annotation surface.
    #
    # Before this endpoint the only "comment" in the product was the single
    # free-text note attached to a workflow approve/reject decision, which meant
    # feedback was impossible outside a formal workflow and could never point at
    # a *region* of an image or a *moment* in a video.
    #
    # PERMISSIONS
    # -----------
    # Commenting requires only +:read+ on the asset's folder, not +:modify+.
    # A comment does not change the asset, and review is precisely the job of
    # people who are *not* allowed to edit — locking commenting behind
    # +:modify+ would exclude the reviewers the feature exists for. Mutating a
    # thread you do not own (resolving, reopening, deleting) does require
    # +:modify+, which is checked in {#authorize_thread_management!}.
    #
    # THREADS ARE VERSION-INDEPENDENT
    # -------------------------------
    # A thread belongs to the asset; each {Comment} inside it records the
    # {AssetVersion} it was written against. Filtering by +version_id+ therefore
    # returns threads that were *discussed on* that version, while the thread
    # itself continues to exist across later versions.
    class CommentThreadsController < ApplicationController
      include CommentSerialization

      before_action :authenticate_hybrid!
      before_action :require_write_scope!, only: %i[create update destroy resolve reopen]
      before_action :set_asset,  only: %i[index create]
      before_action :set_thread, only: %i[show update destroy resolve reopen]

      # GET /api/v1/assets/:asset_id/comments
      #
      # Query params:
      #   version_id  — only threads discussed on that version
      #   status      — open | addressed | verified | resolved
      #   unresolved  — "true" to return only threads still needing action
      #   annotated   — "true" to return only threads anchored to the media
      def index
        # +triaged+ keeps untriaged AI suggestions out of the review. They are
        # real threads, but until a human accepts one it is machine output, not
        # feedback — see AiReviewsController#pending for the triage queue.
        threads = @asset.comment_threads.active.triaged
                        .includes(:created_by, :resolved_by, :origin_version, :ai_review,
                                  comments: [ :author, :asset_version, :annotation_targets, { replies: :author } ])

        threads = threads.for_version(params[:version_id]) if params[:version_id].present?
        threads = threads.where(status: params[:status])    if params[:status].present?
        threads = threads.unresolved                        if truthy?(params[:unresolved])
        threads = threads.where(id: CommentThread.joins(comments: :annotation_targets).select(:id)) if truthy?(params[:annotated])

        threads = threads.order(created_at: :desc)

        render json: {
          threads: threads.map { |t| serialize_thread(t) },
          meta: {
            total: threads.size,
            unresolved: @asset.comment_threads.active.triaged.unresolved.count,
            pending_suggestions: @asset.comment_threads.active.pending_suggestions.count,
          },
        }
      end

      # POST /api/v1/assets/:asset_id/comments
      #
      #   {
      #     "body": "The logo is clipped @jane",
      #     "asset_version_id": "…",     # defaults to the active version
      #     "visibility": "internal",
      #     "motivation": "editing",
      #     "annotations": [
      #       { "shape": "rect", "bbox": { "x": 0.1, "y": 0.2, "w": 0.3, "h": 0.1 },
      #         "source": { "width": 4000, "height": 3000 } }
      #     ]
      #   }
      #
      # Creates the thread and its first comment together — a thread with no
      # comment would be meaningless, so the two are always born in one
      # transaction.
      def create
        version = resolve_version(params[:asset_version_id]) || @asset.active_version

        thread  = nil
        comment = nil

        ActiveRecord::Base.transaction do
          thread = @asset.comment_threads.create!(
            created_by: current_user,
            origin_version: version,
            visibility: params[:visibility].presence || "internal",
          )

          comment = thread.comments.create!(
            body: params.require(:body),
            author: current_user,
            asset_version: version,
            motivation: params[:motivation].presence || "commenting",
          )

          build_annotations!(comment, params[:annotations])
        end

        CommentNotificationService.new(comment).deliver
        # Both events fire: an integration watching for new work wants
        # thread.created, one mirroring the conversation wants comment.created,
        # and the opening comment is genuinely both.
        Comments::EventPublisher.thread_created(thread)
        Comments::EventPublisher.comment_created(comment)

        render json: serialize_thread(thread.reload), status: :created
      rescue ActionController::ParameterMissing => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      # GET /api/v1/comment_threads/:id
      def show
        render json: serialize_thread(@thread)
      end

      # PATCH /api/v1/comment_threads/:id
      # Only +visibility+ is editable directly; status moves through
      # {#resolve}/{#reopen} so resolution attribution is always recorded.
      def update
        return unless authorize_thread_management!

        if @thread.update(visibility: params.require(:visibility))
          render json: serialize_thread(@thread)
        else
          render json: { error: @thread.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end
      rescue ActionController::ParameterMissing => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # DELETE /api/v1/comment_threads/:id
      # Soft-deletes, consistent with the rest of the product (Recycle Bin):
      # review history is evidence and should not silently vanish.
      def destroy
        return unless authorize_thread_management!

        @thread.soft_delete
        head :no_content
      end

      # PATCH /api/v1/comment_threads/:id/resolve
      #   { "status": "resolved" | "verified" }
      #
      # +verified+ is the reviewer confirming a fix actually landed, as opposed
      # to +resolved+ meaning "closed, no further action".
      def resolve
        return unless authorize_thread_management!

        status = params[:status].presence || "resolved"
        unless %w[resolved verified].include?(status)
          return render json: { error: "status must be 'resolved' or 'verified'" }, status: :unprocessable_entity
        end

        @thread.resolve!(user: current_user, status: status)
        CommentNotificationService.new(@thread.comments.active.chronological.first).deliver_resolution(by: current_user)
        Comments::EventPublisher.thread_resolved(@thread)

        render json: serialize_thread(@thread)
      end

      # PATCH /api/v1/comment_threads/:id/reopen
      def reopen
        return unless authorize_thread_management!

        @thread.reopen!
        Comments::EventPublisher.thread_reopened(@thread)
        render json: serialize_thread(@thread)
      end

      private

      def set_asset
        @asset = Asset.active.find_by(id: params[:asset_id]) || Asset.active.find_by!(uuid: params[:asset_id])
        check_asset_read!(@asset)
      end

      def set_thread
        @thread = CommentThread.active.includes(:asset).find(params[:id])
        @asset  = @thread.asset
        check_asset_read!(@asset)
      end

      # Closing, reopening or deleting someone else's thread is a moderation
      # action, so it needs +:modify+ — but the person who opened the thread
      # may always manage their own.
      # @return [Boolean] false when a 403 has already been rendered
      def authorize_thread_management!
        return true if @thread.created_by_id == current_user&.id

        check_asset_modify!(@asset)
        !performed?
      end

      def resolve_version(version_id)
        return nil if version_id.blank?

        @asset.asset_versions.find_by(id: version_id)
      end

      # @param comment [Comment]
      # @param raw_annotations [Array, nil]
      def build_annotations!(comment, raw_annotations)
        Array(raw_annotations).each do |raw|
          comment.annotation_targets.create!(annotation_attributes_from(raw))
        end
      end

      def truthy?(value)
        ActiveModel::Type::Boolean.new.cast(value).present?
      end
    end
  end
end
