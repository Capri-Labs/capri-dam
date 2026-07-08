class Api::V1::CollectionsController < ApplicationController
  include AssetUrlHelper

  # Ensure your API controllers skip CSRF if they are using token auth
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  before_action :authenticate_hybrid!
  before_action :require_write_scope!, only: %i[create update destroy bulk_delete bulk_update add_asset remove_asset toggle_pin configure_rule create_share_link]
  before_action :set_collection, only: [
    :show,
    :update,
    :destroy,
    :add_asset,
    :remove_asset,
    :toggle_pin,
    :configure_rule,
    :cluster_map,
    :purge_cdn,
    :create_share_link,
  ]

  # GET /api/v1/collections
  def index
    # Base scope
    @collections = Collection.active

    #  Temporal Time-Travel Filter
    if params[:as_of].present?
      target_date = Time.zone.parse(params[:as_of]).end_of_day
      @collections = @collections.where("created_at <= ?", target_date)
    end

    @collections = @collections.order(created_at: :desc)

    if params[:asset_id].present?
      pinned_ids = CollectionAsset.where(asset_id: params[:asset_id]).pluck(:collection_id).to_set
      render json: @collections.as_json(methods: [ :assets_count ]).map { |c|
        c.merge("pinned_for_asset" => pinned_ids.include?(c["id"]))
      }, status: :ok
    else
      render json: @collections.as_json(
        methods: [ :assets_count ]
      ), status: :ok
    end
  end

  # PATCH/PUT /api/v1/collections/:slug
  def update
    if @collection.update(collection_params)
      render json: @collection, status: :ok
    else
      render json: { errors: @collection.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/collections/bulk_update
  def bulk_update
    return render json: { error: "No IDs provided" }, status: :bad_request if params[:ids].blank?

    collections = Collection.where(id: params[:ids])

    # Extract just the properties payload for the deep merge
    update_payload = collection_params.to_h
    new_properties = update_payload.delete(:properties) || {}

    # We iterate because updating JSONB requires merging the existing data
    # with the new data, otherwise we overwrite properties we didn't intend to change.
    collections.find_each do |collection|
      current_properties = collection.properties || {}
      merged_properties = current_properties.merge(new_properties)

      collection.update!(
        update_payload.merge(properties: merged_properties)
      )
    end

    render json: { message: "Successfully updated #{collections.count} workspaces." }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  # GET /api/v1/collections/:slug
  def show
    #  Temporal Time-Travel Filter for nested assets
    as_of_date = params[:as_of].present? ? Time.zone.parse(params[:as_of]).end_of_day : Time.current

    json = @collection.as_json(
      methods: [ :compliance_violations ],
      include: {
        collection_rule: {
          only: [ :semantic_prompt, :similarity_threshold, :metadata_filters, :active ],
        },
        collection_assets: {
          # Only show assets that were in the collection as of this date
          conditions: -> { where("collection_assets.created_at <= ?", as_of_date) },
          include: {
            asset: { only: [ :id, :title, :properties, :created_at ] },
          },
          methods: [ :pinned ],
        },
      }
    )

    # `Asset#url`/`#thumbnail_url` aren't real attributes — the actual public
    # URL depends on the active storage backend (ActiveStorage / S3 / GCS /
    # CDN), which `as_json`/`only:` can't resolve. Inject them here via
    # {AssetUrlHelper} so collection asset cards (and share pages) can render
    # a real image instead of a broken/missing thumbnail.
    json["collection_assets"]&.each do |ca_json|
      asset = @collection.collection_assets.find { |ca| ca.id == ca_json["id"] }&.asset
      next unless asset

      ca_json["asset"]["url"] = asset_url_for(asset)
      ca_json["asset"]["thumbnail_url"] = asset_preview_url_for(asset)
    end

    render json: json, status: :ok
  end

  # GET /api/v1/collections/:slug/cluster_map
  def cluster_map
    # In production, this queries your Python FastAPI gateway to run UMAP/t-SNE
    # on the 1536-dimension vectors to flatten them into 2D [x,y] coordinates.
    # Gateway response mock:

    nodes = @collection.assets.map do |asset|
      {
        id: asset.id,
        title: asset.title || asset.original_filename,
        # Mocking the 2D projection distribution (0 to 100 scale)
        x: rand(10.0..90.0).round(2),
        y: rand(10.0..90.0).round(2),
        url: asset.respond_to?(:url) ? asset.url : nil,
      }
    end

    render json: { nodes: nodes }, status: :ok
  end

  # POST /api/v1/collections
  def create
    collection = Collection.new(collection_params)
    collection.user = current_user

    if collection.save
      render json: collection, status: :created
    else
      render json: { errors: collection.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/collections/:slug/assets
  def add_asset
    asset = resolve_asset(params[:asset_id])
    return render json: { error: "Asset not found" }, status: :not_found unless asset

    join_record = CollectionAsset.new(collection: @collection, asset: asset)

    if join_record.save
      render json: { message: "Asset added successfully", collection: @collection.as_json }, status: :ok
    else
      render json: { errors: join_record.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/collections/:slug/assets/:asset_id
  def remove_asset
    asset = resolve_asset(params[:asset_id])
    join_record = asset && CollectionAsset.find_by(collection: @collection, asset_id: asset.id)

    if join_record
      join_record.destroy
      render json: { message: "Asset removed successfully" }, status: :ok
    else
      render json: { error: "Asset not found in this collection" }, status: :not_found
    end
  end

  # POST /api/v1/collections/:slug/rule
  def configure_rule
    # Ensure the collection is marked as 'smart'
    @collection.update!(collection_type: "smart") unless @collection.smart?

    rule = @collection.collection_rule || @collection.build_collection_rule

    # Assign the new parameters
    rule.semantic_prompt = params[:semantic_prompt]
    rule.similarity_threshold = params[:similarity_threshold] || 0.800
    rule.metadata_filters = params[:metadata_filters] || {}
    rule.active = params[:active].nil? ? true : params[:active]

    if rule.save
      render json: {
        message: "Smart routing rules updated successfully.",
        collection: @collection.as_json(include: :collection_rule),
      }, status: :ok
    else
      render json: { errors: rule.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/collections/:slug/assets/:asset_id/pin
  def toggle_pin
    asset = resolve_asset(params[:asset_id])
    join_record = asset && CollectionAsset.find_by(collection: @collection, asset_id: asset.id)

    return render json: { error: "Asset not in collection" }, status: :not_found unless join_record

    # Toggle the boolean state
    join_record.update!(pinned: !join_record.pinned)

    status_message = join_record.pinned ? "Asset pinned manually." : "Asset unpinned. AI will manage routing."
    render json: { message: status_message, pinned: join_record.pinned }, status: :ok
  end

  # DELETE /api/v1/collections/:slug
  def destroy
    # Soft delete to maintain audit trails
    if @collection.update(deleted_at: Time.current)
      render json: { message: "Workspace archived successfully." }, status: :ok
    else
      render json: { error: "Failed to archive workspace." }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/collections/bulk_delete
  def bulk_delete
    # Verify we received an array of IDs
    return render json: { error: "No IDs provided" }, status: :bad_request if params[:ids].blank?

    collections = Collection.where(id: params[:ids])

    # Soft delete all matched records in a single query
    deleted_count = collections.update_all(deleted_at: Time.current)

    render json: { message: "Successfully archived #{deleted_count} workspaces." }, status: :ok
  end

  # POST /api/v1/collections/:slug/purge_cdn
  def purge_cdn
    # In production, this would trigger a Sidekiq worker to hit the CloudFront/Akamai API
    # CdnPurgeWorker.perform_async(@collection.id)

    render json: { message: "CDN Cache invalidation initiated for #{@collection.name}." }, status: :ok
  end

  # POST /api/v1/collections/:slug/share_link
  #
  # Mints a time-boxed, tamper-proof signed token (see {Collection#generate_share_token})
  # and returns the fully-qualified public URL an unauthenticated visitor can
  # open at {Public::CollectionSharesController#show} to view a read-only,
  # login-free snapshot of the collection's assets.
  def create_share_link
    expires_in = Collection::SHARE_LINK_EXPIRY
    token = @collection.generate_share_token(expires_in: expires_in)

    render json: {
      token: token,
      url: public_collection_share_url(token: token),
      expires_at: expires_in.from_now.iso8601,
    }, status: :ok
  end

  # POST /api/v1/collections/simulate_rule
  def simulate_rule
    prompt = params.require(:semantic_prompt)
    threshold = params[:similarity_threshold].to_f

    # --- ENTERPRISE VECTOR LOGIC ---
    # 1. Fetch the vector embedding for the human prompt from your AI Gateway
    # prompt_vector = AiGatewayClient.get_embedding(prompt)

    # 2. Perform the Cosine Similarity search using pgvector
    # simulated_matches = Asset.joins(:asset_embedding)
    #                          .where("1 - (asset_embeddings.embedding <=> ?) >= ?", prompt_vector, threshold)
    #                          .order(Arel.sql("asset_embeddings.embedding <=> '#{prompt_vector}'"))
    #                          .limit(20)

    # --- DEVELOPMENT MOCK (Replace with logic above in Production) ---
    # Simulates finding 4 to 12 assets with random match scores above the threshold
    simulated_matches = Asset.published.order(Arel.sql("RANDOM()")).limit(rand(4..12)).map do |asset|
      asset.as_json(only: [ :id, :title, :properties ]).merge(
        mock_match_score: (threshold + rand(0.01..(1.0 - threshold))).round(3)
      )
    end

    render json: {
      matches: simulated_matches,
      count: simulated_matches.size,
      message: "Simulation complete.",
    }, status: :ok
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  end

  private

  def set_collection
    @collection = Collection.active.find_by!(slug: params[:slug])

    # Enforce Security on the detailed view
    unless @collection.accessible_by?(current_user)
      render json: { error: "Unauthorized Access: You do not have clearance for this workspace." }, status: :forbidden
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Collection not found" }, status: :not_found
  end

  # Assets are addressable by either their primary key (+id+) or their public
  # +uuid+ column (the value returned by search/suggestion endpoints), so any
  # asset_id param coming from the client may be either.
  def resolve_asset(asset_id)
    return nil if asset_id.blank?

    Asset.find_by(id: asset_id) || Asset.find_by(uuid: asset_id)
  end

  def collection_params
    # We explicitly permit the nested JSON keys for strict parameters
    params.require(:collection).permit(
      :name,
      :description,
      :collection_type,
      :expires_at,
      properties: [
        tags: [],
        allowed_groups: [],
        denied_groups: [],
      ]
    )
  end
end
