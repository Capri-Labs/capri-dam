class Api::V1::AssetEmbeddingsController < ApplicationController
  skip_before_action :verify_authenticity_token
  # before_action :verify_microservice_token!

  # PUT/PATCH /api/v1/assets/:asset_id/embedding
  def update
    asset = Asset.find(params[:asset_id])

    # We use find_or_initialize_by so that if the metadata is updated later,
    # the AI simply overwrites the old vector instead of duplicating rows.
    embedding_record = asset.asset_embedding || asset.build_asset_embedding

    embedding_record.assign_attributes(
      embedding: embedding_params[:embedding],
      model_name: embedding_params[:model_name]
    )

    if embedding_record.save
      render json: { message: "Vector spatial index updated" }, status: :ok
    else
      render json: { errors: embedding_record.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def embedding_params
    params.require(:asset_embedding).permit(:model_name, embedding: [])
  end
end