class Api::V1::IngestionItemsController < ApplicationController
  skip_before_action :verify_authenticity_token
  # Ingestion items are updated by the connector microservice via PAT (admin scope)
  # or by authenticated admin users.
  before_action :authenticate_hybrid!
  before_action :require_admin!

  # GET /api/v1/ingestion_items/:id
  def show
    item = IngestionItem.find(params[:id])
    render json: item, status: :ok
  end

  # PATCH /api/v1/ingestion_items/:id
  def update
    item = IngestionItem.find(params[:id])

    if item.update(ingestion_item_params)
      # If the batch has no more pending/processing items, update the batch status
      check_batch_completion(item.ingestion_batch)

      render json: { message: "Item updated successfully" }, status: :ok
    else
      render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def ingestion_item_params
    params.require(:ingestion_item).permit(:status, :error_log, clean_properties: {})
  end

  def check_batch_completion(batch)
    # If no items are pending or processing, the transformation phase is complete
    active_items = batch.ingestion_items.where(status: [ :pending, :ai_processing ]).count

    if active_items.zero? && batch.transforming?
      batch.review_needed!
    end
  end
end
