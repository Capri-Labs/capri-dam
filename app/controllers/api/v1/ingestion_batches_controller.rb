class Api::V1::IngestionBatchesController < ApplicationController
  skip_before_action :verify_authenticity_token
  # before_action :authenticate_user!

  # POST /api/v1/ingestion_batches
  def create
    batch = IngestionBatch.new(batch_params)
    # batch.user_id = current_user.id
    batch.status = :initializing

    if batch.save
      # Immediately hand off to Sidekiq so the Rails thread doesn't block
      ExtractionWorker.perform_async(batch.id)

      render json: { message: "Extraction pipeline initialized", batch: batch }, status: :created
    else
      render json: { errors: batch.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def batch_params
    # We permit the JSONB credentials block to pass through
    params.require(:ingestion_batch).permit(:name, :source_type, source_credentials: {})
  end
end