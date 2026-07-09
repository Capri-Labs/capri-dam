class Api::V1::IngestionBatchesController < ApplicationController
  before_action :authenticate_hybrid!
  before_action :require_admin!, only: %i[commit abort destroy]
  before_action :set_batch, only: %i[show commit abort report destroy]

  # GET /api/v1/ingestion_batches
  # Supports: ?status=committed&source_type=aem&search=Q&page=1
  def index
    scope = IngestionBatch.order(created_at: :desc)
    scope = scope.where(status: params[:status])                    if params[:status].present?
    scope = scope.where(source_type: params[:source_type])          if params[:source_type].present?
    scope = scope.search_by_name(params[:search])                   if params[:search].present?

    page     = [ params[:page].to_i, 1 ].max
    per_page = 50
    batches  = scope.limit(per_page).offset((page - 1) * per_page)

    render json: {
      batches: batches.map(&:summary),
      meta:    { total: scope.count, page: page, per_page: per_page },
    }
  end

  # GET /api/v1/ingestion_batches/stats
  def stats
    render json: IngestionBatch.aggregate_stats
  end

  # GET /api/v1/ingestion_batches/:id
  def show
    items_scope = @batch.ingestion_items.order(:id)
    items_scope = items_scope.where(status: params[:status]) if params[:status].present?

    page     = [ params[:page].to_i, 1 ].max
    per_page = 50
    items    = items_scope.limit(per_page).offset((page - 1) * per_page)

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
          full_metadata:     item.full_metadata,
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
  def commit
    unless @batch.review_needed?
      return render json: { error: "Batch must be in 'review_needed' state to commit. Current: #{@batch.status}" },
                    status: :unprocessable_entity
    end

    MigrationCommitWorker.perform_async(@batch.id)
    render json: { message: "Commit pipeline started. You will receive an email when complete.", batch: @batch.summary }
  end

  # POST /api/v1/ingestion_batches/:id/abort
  def abort
    if @batch.committed?
      return render json: { error: "Cannot abort a committed batch." }, status: :unprocessable_entity
    end

    @batch.update!(status: :failed, completed_at: Time.current)
    render json: { message: "Migration batch aborted.", batch: @batch.summary }
  end

  # DELETE /api/v1/ingestion_batches/:id
  # Only failed batches may be deleted.
  def destroy
    unless @batch.failed?
      return render json: { error: "Only failed batches can be deleted." }, status: :unprocessable_entity
    end

    @batch.destroy!
    render json: { message: "Migration batch deleted." }
  end

  # GET /api/v1/ingestion_batches/:id/report
  def report
    if @batch.report_snapshot_id.present?
      snapshot = ReportSnapshot.find_by(id: @batch.report_snapshot_id)
      stats    = snapshot&.parameters&.dig("stats") || {}
    else
      stats = {}
    end

    if stats.empty? && @batch.committed?
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
      :name, :source_type, :connector_id, :notes, :destination_folder_id,
      :migrate_metadata,
      source_credentials: {}
    )
  end
end
