class Api::V1::CollectionsController < ApplicationController
  # Ensure your API controllers skip CSRF if they are using token auth
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  before_action :set_collection, only: [:show, :add_asset, :remove_asset]

  # GET /api/v1/collections
  def index
    collections = Collection.active.order(created_at: :desc)
    render json: collections, status: :ok
  end

  # GET /api/v1/collections/:slug
  def show
    # Renders the collection and includes the nested asset details
    render json: @collection.as_json(include: :assets), status: :ok
  end

  # POST /api/v1/collections
  def create
    collection = Collection.new(collection_params)
    # collection.user = current_user

    if collection.save
      render json: collection, status: :created
    else
      render json: { errors: collection.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/collections/:slug/assets
  def add_asset
    asset = Asset.find_by(id: params[:asset_id])
    return render json: { error: 'Asset not found' }, status: :not_found unless asset

    join_record = CollectionAsset.new(collection: @collection, asset: asset)

    if join_record.save
      render json: { message: 'Asset added successfully', collection: @collection.as_json }, status: :ok
    else
      render json: { errors: join_record.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/collections/:slug/assets/:asset_id
  def remove_asset
    join_record = CollectionAsset.find_by(collection: @collection, asset_id: params[:asset_id])

    if join_record
      join_record.destroy
      render json: { message: 'Asset removed successfully' }, status: :ok
    else
      render json: { error: 'Asset not found in this collection' }, status: :not_found
    end
  end

  private

  def set_collection
    @collection = Collection.active.find_by!(slug: params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Collection not found' }, status: :not_found
  end

  def collection_params
    # Permit properties for future AI prompt injection
    params.require(:collection).permit(:name, :description, properties: {})
  end
end