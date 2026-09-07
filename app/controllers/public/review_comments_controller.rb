module Public
  # Lets an external reviewer post feedback through a {ReviewLink}.
  #
  # Every write here is constrained in three ways that the internal endpoints
  # do not need:
  #
  # * *Scope* — the asset must be one the link covers, resolved via
  #   {ReviewLink#scoped_assets} rather than a bare lookup.
  # * *Visibility* — anything a guest creates is forced to +guest+ visibility.
  #   A guest writing an +internal+ thread would be invisible to them the
  #   moment it was saved, and would pollute the internal tier with outside
  #   content.
  # * *Attribution* — the author is the {ReviewGuest}, never a {User}. There is
  #   no code path here that can set +author_id+.
  #
  # Guests can open threads and reply. They cannot resolve, verify, reopen,
  # edit or delete: closing feedback is a decision for the people accountable
  # for the asset, and a client marking their own objection resolved would
  # destroy the audit trail the review exists to produce.
  class ReviewCommentsController < ApplicationController
    include ReviewLinkAuthentication
    include GuestReviewSerialization

    # A cap, because this endpoint is reachable by anyone with the URL and an
    # unbounded array would be an easy way to bloat the database.
    MAX_ANNOTATIONS_PER_COMMENT = 20

    before_action :require_commenting_allowed
    before_action :set_asset, only: %i[create]
    before_action :set_thread, only: %i[reply]

    # Writing is more expensive and more abusable than reading, so it is
    # throttled harder than the read endpoints.
    rate_limit to: 20, within: 1.minute,
               with: -> { render json: { error: "You are commenting too quickly. Please wait a moment." }, status: :too_many_requests }

    # POST /s/reviews/:token/assets/:asset_id/comments
    #
    # Opens a thread with its first comment, mirroring
    # {Api::V1::CommentThreadsController#create} but with guest attribution.
    def create
      guest = review_guest_for_write!
      thread = nil
      comment = nil

      ActiveRecord::Base.transaction do
        thread = @asset.comment_threads.create!(
          created_by_guest: guest,
          review_link: @review_link,
          origin_version: @asset.active_version,
          # Forced, never taken from params.
          visibility: "guest",
        )

        comment = thread.comments.create!(
          body: params.require(:body),
          review_guest: guest,
          asset_version: @asset.active_version,
          motivation: params[:motivation].presence || "commenting",
        )

        build_guest_annotations!(comment, params[:annotations])
      end

      notify_internal(comment)
      render json: { thread: serialize_guest_thread(thread.reload) }, status: :created
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    # POST /s/reviews/:token/threads/:thread_id/comments
    def reply
      guest = review_guest_for_write!
      comment = @thread.comments.create!(
        body: params.require(:body),
        review_guest: guest,
        asset_version: @thread.asset.active_version,
        parent_comment: resolve_parent,
        motivation: params[:motivation].presence || "replying",
      )

      notify_internal(comment)
      render json: { comment: serialize_guest_comment(comment) }, status: :created
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    private

    def require_commenting_allowed
      return if can_comment?

      if !@review_link.allow_comments?
        render json: { error: "This review link is read-only." }, status: :forbidden
      else
        # The link wants a name against the feedback and does not have one yet.
        render json: { error: "Please tell us who you are before commenting.", reason: "identify_required" },
               status: :unauthorized
      end
    end

    def set_asset
      @asset = scoped_asset(params[:asset_id])
      render json: { error: "Not found" }, status: :not_found if @asset.nil?
    end

    # Resolves the thread *through the link's scope*, so a guest cannot reply
    # into a thread on an asset the link does not cover by guessing its id —
    # and cannot reply into an internal thread even on an asset it does.
    def set_thread
      @thread = CommentThread.active
                             .visible_to_guests
                             .where(asset_id: @review_link.scoped_assets.select(:id))
                             .find_by(id: params[:thread_id])

      render json: { error: "Not found" }, status: :not_found if @thread.nil?
    end

    def resolve_parent
      return nil if params[:parent_comment_id].blank?

      # Constrained to this thread; anything else is treated as no parent
      # rather than 404ing, since a stale id should not lose the reviewer their
      # typed comment.
      @thread.comments.active.find_by(id: params[:parent_comment_id])
    end

    # Guests get the same geometry pipeline as internal reviewers — the whole
    # point is that they can draw on the image — but the payload goes through
    # the same whitelist, so nothing beyond the known annotation columns can be
    # set from an unauthenticated request.
    def build_guest_annotations!(comment, raw_annotations)
      Array(raw_annotations).first(MAX_ANNOTATIONS_PER_COMMENT).each do |raw|
        comment.annotation_targets.create!(annotation_attributes_from(raw))
      end
    end

    # Tells the internal team that the client has said something. Guests are
    # not mentioned-notified themselves, and a failure here must not lose the
    # comment that has already been committed.
    def notify_internal(comment)
      Comments::EventPublisher.comment_created(comment)
    rescue StandardError => e
      Rails.logger.error("[Public::ReviewComments] notification failed for #{comment.id}: #{e.message}")
    end
  end
end
