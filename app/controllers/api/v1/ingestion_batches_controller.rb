class Api::V1::IngestionBatchesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_batch, only: [ :show, :commit, :abort, :report ]

  # GET /api/v1/ingestion_batches
  def index
    batches = IngestionBatch.order(created_at: :desc).limit(50)
    render json: batches.map(&:summary)
  end

  # GET /api/v1/ingestion_batches/:id
  def show
    items_scope = @batch.ingestion_items.order(:id)

    # Filtering
    items_scope = items_scope.where(status: params[:status]) if params[:status].present?

    # Pagination (cursor)
    page     = [ params[:page].to_i, 1 ].max
    per_page = 50
    items    = items_scope.page(page).per(per_page) rescue items_scope.limit(per_page).offset((page - 1) * per_page)

    render json: {
      batch: @batch.summary,
      items: items.map { |item|
        {
          id:                item.id,
          original_filename: item.original_filename,
          file_hash:         item.file_hash,
          file_size:         item.file_size,
          status:            item.status,
          error_log:         item.error_log,
          legacy_metadata:   item.legacy_metadata,
          clean_properties:  item.clean_properties,
          created_at:        item.created_at,
        }
      },
      meta: {
        total:    items_scope.count,
        page:     page,
        per_page: per_page,
      },
    }
  end

  # POST /api/v1/ingestion_batches
  def create
    batch = IngestionBatch.new(batch_params)
    batch.status          = :initializing
    batch.initiated_by_id = current_user.id
    batch.started_at      = Time.current

    if batch.save
      ExtractionWorker.perform_async(batch.id)
      render json: { message: "Migration pipeline initialized.", batch: batch.summary }, status: :created
    else
      render json: { errors: batch.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/ingestion_batches/:id/commit
  # Human approves the batch after reviewing it in BatchReviewWorkspace.
  def commit
    unless @batch.review_needed?
      return render json: { error: "Batch must be in 'review_needed' state to commit. Current: #{@batch.status}" },
                    status: :unprocessable_entity
    end

    MigrationCommitWorker.perform_async(@batch.id)
    render json: { message: "Commit pipeline started. You will receive an email when complete.", batch: @batch.summary }
  end

  # POST /api/v1/ingestion_batches/:id/abort
  # Abandon the migration without committing.
  def abort
    if @batch.committed?
      return render json: { error: "Cannot abort a committed batch." }, status: :unprocessable_entity
    end

    @batch.update!(status: :failed, completed_at: Time.current)
    render json: { message: "Migration batch aborted.", batch: @batch.summary }
  end

  # GET /api/v1/ingestion_batches/:id/report
  # Returns the migration report stats. Triggers generation if not yet done.
  def report
    if @batch.report_snapshot_id.present?
      snapshot = ReportSnapshot.find_by(id: @batch.report_snapshot_id)
      stats    = snapshot&.parameters&.dig("stats") || {}
    else
      stats = {}
    end

    if stats.empty? && @batch.committed?
      # Trigger generation in background if not yet done
      MigrationReportWorker.perform_async(@batch.id)
      return render json: { message: "Report is being generated. Check back shortly." }, status: :accepted
    end

    render json: { batch: @batch.summary, report: stats }
  end

  private

  def set_batch
    @batch = IngestionBatch.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Batch not found" }, status: :not_found
  end

  def batch_params
    params.require(:ingestion_batch).permit(
      :name, :source_type, :connector_id, :notes,
      source_credentials: {}
    )
  end
end
