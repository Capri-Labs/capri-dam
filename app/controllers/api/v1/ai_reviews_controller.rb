module Api
  module V1
    # The AI review assistant: runs a vision model over an asset and posts its
    # findings as real annotated comments for a human to triage.
    #
    # PERMISSIONS
    # -----------
    # Requesting a review requires +:modify+, not the +:read+ that ordinary
    # commenting needs. Two reasons: a run sends the asset to an external
    # inference service, which is a disclosure decision rather than a reading
    # one; and it costs money against the configured AI budget. Accepting or
    # dismissing a suggestion likewise requires +:modify+, because accepting is
    # what turns machine output into part of the team's review record.
    #
    # WHY SUGGESTIONS ARE NOT JUST COMMENTS
    # -------------------------------------
    # Findings are stored as ordinary threads (so they keep annotation
    # geometry, version binding and diffing) but carry
    # +suggestion_state: "pending"+, which excludes them from every human and
    # guest listing until somebody accepts one. A model's guess must never
    # arrive in a client's review as though a colleague had written it.
    class AiReviewsController < ApplicationController
      include CommentSerialization

      before_action :authenticate_hybrid!, except: %i[findings]
      before_action :require_write_scope!, only: %i[create accept dismiss]
      # The gateway is a machine caller with no user session; it proves itself
      # with the shared secret instead.
      skip_before_action :verify_authenticity_token, only: %i[findings], raise: false
      before_action :authenticate_gateway_secret!, only: %i[findings]

      before_action :set_asset, only: %i[index create pending]
      before_action :set_review, only: %i[show findings]
      before_action :set_thread, only: %i[accept dismiss]

      PAGE_SIZE = 25

      # GET /api/v1/assets/:asset_id/ai_reviews
      def index
        reviews = AiReview.for_asset(@asset).recent.limit(PAGE_SIZE)

        render json: { reviews: reviews.map { |r| serialize_review(r) } }
      end

      # POST /api/v1/assets/:asset_id/ai_reviews
      def create
        check_asset_modify!(@asset)
        return if performed?

        # A second run while one is in flight would duplicate every finding
        # into the triage queue.
        if AiReview.for_asset(@asset).in_flight.exists?
          return render json: { error: "A review is already running for this asset." },
                        status: :conflict
        end

        review = AiReview.new(
          asset: @asset,
          asset_version: @asset.try(:active_version),
          requested_by: current_user,
          profile: params[:profile].presence || "brand_guidelines",
          options: options_param,
        )
        review.ai_model_name = vision_model&.model_id
        review.provider = vision_model&.provider

        unless review.save
          return render json: { errors: review.errors.full_messages }, status: :unprocessable_content
        end

        AiReviewWorker.perform_async(review.id)

        render json: { review: serialize_review(review) }, status: :created
      end

      # GET /api/v1/ai_reviews/:id
      def show
        check_asset_read!(@review.asset)
        return if performed?

        render json: { review: serialize_review(@review) }
      end

      # GET /api/v1/assets/:asset_id/ai_reviews/pending
      # The triage queue: suggestions awaiting a human decision.
      def pending
        check_asset_read!(@asset)
        return if performed?

        threads = @asset.comment_threads.active.pending_suggestions
                        .includes(:ai_review,
                                  comments: [ :annotation_targets, :asset_version ])
                        .order(created_at: :desc)

        render json: { threads: threads.map { |t| serialize_thread(t) } }
      end

      # POST /api/v1/ai_reviews/:id/findings
      # Called by the AI gateway, not by a user.
      def findings
        if @review.terminal?
          # Late or replayed delivery. Accepting it would duplicate findings
          # already triaged, so it is reported as handled and ignored.
          return render json: { status: "ignored", reason: "review already #{@review.status}" }
        end

        if params[:error].present?
          @review.fail!(params[:error])
          return render json: { status: "failed" }
        end

        # Root-scoped: an Api::V1::Ai module exists (the lab controller), so a
        # bare Ai:: would resolve there and fail at runtime.
        result = ::Ai::ReviewFindingImporter.new(@review).import(params[:findings])

        render json: {
          status: "ok",
          imported: result.imported,
          skipped: result.skipped,
          errors: result.errors,
        }
      end

      # POST /api/v1/comment_threads/:id/accept_suggestion
      def accept
        apply_decision(:accept)
      end

      # POST /api/v1/comment_threads/:id/dismiss_suggestion
      def dismiss
        apply_decision(:dismiss)
      end

      private

      def apply_decision(decision)
        check_asset_modify!(@thread.asset)
        return if performed?

        unless @thread.pending_suggestion?
          return render json: { error: "This thread is not a pending suggestion." },
                        status: :unprocessable_content
        end

        if decision == :accept
          @thread.accept_suggestion!(user: current_user)
        else
          @thread.dismiss_suggestion!(user: current_user)
        end

        render json: { thread: serialize_thread(@thread.reload) }
      end

      def set_asset
        @asset = Asset.find(params[:asset_id])
        check_asset_read!(@asset)
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Asset not found" }, status: :not_found
      end

      def set_review
        @review = AiReview.includes(:asset).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Review not found" }, status: :not_found
      end

      def set_thread
        @thread = CommentThread.active.includes(:asset).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Thread not found" }, status: :not_found
      end

      # Only a bounded set of knobs is forwarded. The instruction itself comes
      # from the profile allow-list, so this endpoint cannot be used to run
      # arbitrary prompts against a customer's assets.
      def options_param
        raw = params[:options]
        return {} if raw.blank?

        permitted = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
        permitted.with_indifferent_access.slice(:brand_kit_id, :locale, :strictness)
      end

      def vision_model
        @vision_model ||= AiModelConfig.for_capability("vision").enabled.defaults.first ||
                          AiModelConfig.for_capability("vision").enabled.first
      end

      def serialize_review(review)
        {
          id: review.id,
          asset_id: review.asset_id,
          asset_version_id: review.asset_version_id,
          status: review.status,
          profile: review.profile,
          profile_label: review.profile_label,
          model_name: review.ai_model_name,
          provider: review.provider,
          findings_count: review.findings_count,
          error_message: review.error_message,
          requested_by: review.requested_by&.email,
          started_at: review.started_at,
          completed_at: review.completed_at,
          created_at: review.created_at,
        }
      end

      def authenticate_gateway_secret!
        expected = Rails.application.credentials.dig(:ai_gateway, :secret).presence ||
                   ENV.fetch("GATEWAY_SECRET", nil)
        received = request.headers["X-Gateway-Secret"]

        return if expected.present? &&
                  ActiveSupport::SecurityUtils.secure_compare(expected, received.to_s)

        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
  end
end
