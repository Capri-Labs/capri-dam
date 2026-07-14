# frozen_string_literal: true

# Handles semantic vector-search requests forwarded from the Semantic Copilot UI.
#
# The embedding is fetched from the AI Gateway (Faraday) then used for a
# pgvector HNSW nearest-neighbour query.  Results include a `similarity_score`
# (1 - cosine_distance) so the frontend can render confidence bars.
#
# POST /api/v1/copilot/search
class Api::V1::CopilotsController < ApplicationController
  include AssetUrlHelper

  before_action :authenticate_hybrid!

  DEFAULT_LIMIT = 20
  MAX_LIMIT     = 50

  # POST /api/v1/copilot/search
  #
  # Params:
  #   query        [String]  required  natural-language search string
  #   limit        [Integer] optional  max results (1–50, default 20)
  #   content_type [String]  optional  filter e.g. "image", "video", "document"
  def search
    query = params[:query].to_s.strip
    return render json: { results: [], query: "", count: 0 }, status: :ok if query.blank?

    limit        = params.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
    content_type = params[:content_type].presence

    query_vector = fetch_query_embedding(query)
    assets       = build_query(query_vector, content_type).limit(limit)

    render json: {
      query:   query,
      count:   assets.size,
      results: assets.map { |a| serialize_asset(a) },
    }, status: :ok
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    render json: { error: "AI Gateway unavailable: #{e.message}" }, status: :service_unavailable
  rescue Faraday::Error => e
    Rails.logger.error("[CopilotsController#search] #{e.message}")
    render json: { error: "Failed to process semantic query." }, status: :internal_server_error
  end

  private

  def build_query(vector, content_type)
    rel = Asset.nearest_to_vector(vector)
              .includes(:active_version, :folder)
              .where(deleted_at: nil)

    if content_type.present?
      # content_type is stored as e.g. "image/jpeg" in asset_versions.properties
      rel = rel.joins(:active_version)
               .where("asset_versions.properties->>'content_type' ILIKE ?", "#{content_type}/%")
    end

    rel
  end

  # Returns a richer payload for the Semantic Copilot UI.
  # `neighbor_distance` (0–1, lower = more similar) is exposed as
  # `similarity_score` (0–1, higher = more similar) by inverting it.
  def serialize_asset(asset)
    active_v  = asset.active_version
    v_props   = active_v&.properties || {}
    a_props   = asset.properties || {}
    merged    = a_props.merge(v_props)

    {
      id:                asset.id,
      title:             asset.title.presence || asset.original_filename,
      original_filename: asset.original_filename,
      status:            asset.status,
      content_type:      merged["content_type"],
      file_size:         merged["file_size"],
      width:             merged["width"],
      height:            merged["height"],
      folder_name:       asset.folder&.name,
      folder_id:         asset.folder_id,
      tags:              Array(merged["tags"]),
      description:       merged["description"],
      campaign:          merged["campaign"],
      url:               asset_url_for(asset),
      # similarity_score: 1.0 means perfect match, 0.0 means unrelated.
      # neighbor_distance is cosine distance (0=identical, 1=orthogonal).
      similarity_score:  asset.respond_to?(:neighbor_distance) && asset.neighbor_distance ?
                           (1.0 - asset.neighbor_distance).round(4) : nil,
    }
  end

  def fetch_query_embedding(text)
    response = gateway_client.post("/api/embed_query", { text: text })
    raise "AI Gateway Error: #{response.status}" unless response.success?

    response.body["vector"]
  end

  def gateway_client
    @gateway_client ||= Faraday.new(url: ai_gateway_url) do |conn|
      conn.request  :json
      conn.response :json
      conn.options.timeout      = 30
      conn.options.open_timeout = 5
      conn.adapter Faraday.default_adapter
    end
  end

  def ai_gateway_url
    Rails.application.credentials.dig(:ai_gateway, :url).presence ||
      ENV.fetch("AI_GATEWAY_URL", "http://localhost:8000")
  end
end
