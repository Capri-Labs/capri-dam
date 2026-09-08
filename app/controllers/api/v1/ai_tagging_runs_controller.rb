module Api
  module V1
    # Automatic tag suggestions from a vision model.
    #
    # THE INVARIANT THIS CONTROLLER PROTECTS
    # --------------------------------------
    # Nothing here writes a machine-derived label into the asset's real tags
    # except {#accept}, which requires a signed-in user with modify rights. The
    # gateway callback can only ever create *pending* suggestions. A model's
    # guess must never appear in the library's vocabulary as though a curator
    # had put it there.
    class AiTaggingRunsController < ApplicationController
      before_action :authenticate_hybrid!, except: %i[suggestions]
      # The gateway is a machine caller with no user session; it proves itself
      # with the shared secret instead.
      skip_before_action :verify_authenticity_token, only: %i[suggestions], raise: false
      before_action :authenticate_gateway_secret!, only: %i[suggestions]

      before_action :set_asset, only: %i[index create pending]
      before_action :set_run,   only: %i[show suggestions]
      before_action :set_suggestion, only: %i[accept dismiss]

      PAGE_SIZE = 25

      # GET /api/v1/assets/:asset_id/ai_tagging_runs
      def index
        check_asset_read!(@asset)
        return if performed?

        runs = AiTaggingRun.where(asset_id: @asset.id).recent.limit(PAGE_SIZE)

        render json: { runs: runs.map { |r| serialize_run(r) } }
      end

      # GET /api/v1/assets/:asset_id/ai_tag_suggestions
      #
      # The triage queue: what the machine proposes that nobody has ruled on.
      def pending
        check_asset_read!(@asset)
        return if performed?

        suggestions = AiTagSuggestion.where(asset_id: @asset.id)
                                     .pending
                                     .order(confidence: :desc)

        render json: { suggestions: suggestions.map { |s| serialize_suggestion(s) } }
      end

      # POST /api/v1/assets/:asset_id/ai_tagging_runs
      def create
        check_asset_modify!(@asset)
        return if performed?

        # A second run while one is in flight would propose the same labels
        # twice and double the triage burden for no new information.
        if AiTaggingRun.where(asset_id: @asset.id).in_flight.exists?
          return render json: { error: "A tagging run is already in progress for this asset." },
                        status: :conflict
        end

        run = AiTaggingRun.new(
          asset: @asset,
          asset_version: @asset.try(:active_version),
          requested_by: current_user,
          trigger: "manual",
          profile: requested_profile,
        )

        if run.save
          AiAutoTagWorker.perform_async(run.id)
          render json: serialize_run(run), status: :created
        else
          render json: { errors: run.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/ai_tagging_runs/:id
      def show
        check_asset_read!(@run.asset)
        return if performed?

        render json: serialize_run(@run).merge(
          suggestions: @run.ai_tag_suggestions.map { |s| serialize_suggestion(s) },
        )
      end

      # POST /api/v1/ai_tagging_runs/:id/suggestions  (gateway callback)
      def suggestions
        # Late or replayed delivery. Accepting it would duplicate every label
        # against a run that has already been reported as finished.
        if @run.terminal?
          return render json: { error: "Run already #{@run.status}." }, status: :conflict
        end

        if params[:error].present?
          @run.fail!(params[:error])
          return render json: { status: @run.status }, status: :ok
        end

        result = ::Ai::TagSuggestionImporter.new(@run).import(params[:suggestions])

        render json: {
          status: @run.reload.status,
          imported: result.imported,
          skipped: result.skipped,
          errors: result.errors,
        }, status: :ok
      end

      # POST /api/v1/ai_tag_suggestions/:id/accept
      #
      # The only path in the system that promotes a machine label into the
      # asset's real tags.
      def accept
        check_asset_modify!(@suggestion.asset)
        return if performed?

        unless @suggestion.pending?
          return render json: { error: "Already #{@suggestion.state}." }, status: :conflict
        end

        @suggestion.accept!(user: current_user)
        render json: serialize_suggestion(@suggestion)
      end

      # POST /api/v1/ai_tag_suggestions/:id/dismiss
      def dismiss
        check_asset_modify!(@suggestion.asset)
        return if performed?

        unless @suggestion.pending?
          return render json: { error: "Already #{@suggestion.state}." }, status: :conflict
        end

        @suggestion.dismiss!(user: current_user)
        render json: serialize_suggestion(@suggestion)
      end

      private

      def set_asset
        @asset = Asset.find_by(id: params[:asset_id]) || Asset.find_by(uuid: params[:asset_id])
        render json: { error: "Asset not found" }, status: :not_found if @asset.nil?
      end

      def set_run
        @run = AiTaggingRun.find_by(id: params[:id])
        render json: { error: "Run not found" }, status: :not_found if @run.nil?
      end

      def set_suggestion
        @suggestion = AiTagSuggestion.find_by(id: params[:id])
        render json: { error: "Suggestion not found" }, status: :not_found if @suggestion.nil?
      end

      # Allow-listed, never a free-text prompt: a client that could dictate the
      # instruction could redirect the model to do something other than tagging
      # under our credentials.
      def requested_profile
        candidate = params[:profile].to_s
        AiTaggingRun::PROFILES.key?(candidate) ? candidate : "general_subject"
      end

      def serialize_run(run)
        {
          id: run.id,
          asset_id: run.asset_id,
          status: run.status,
          profile: run.profile,
          trigger: run.trigger,
          model_name: run.ai_model_name,
          provider: run.provider,
          suggestions_count: run.suggestions_count,
          error_message: run.error_message,
          requested_by: run.requested_by&.email,
          started_at: run.started_at,
          completed_at: run.completed_at,
          created_at: run.created_at,
        }
      end

      def serialize_suggestion(suggestion)
        {
          id: suggestion.id,
          asset_id: suggestion.asset_id,
          run_id: suggestion.ai_tagging_run_id,
          label: suggestion.label,
          confidence: suggestion.confidence,
          state: suggestion.state,
          decided_by: suggestion.decided_by&.email,
          decided_at: suggestion.decided_at,
          created_at: suggestion.created_at,
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
