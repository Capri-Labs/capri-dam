require "net/http"
require "uri"

class Api::V1::CopilotsController < ApplicationController
  # before_action :authenticate_user!

  # POST /api/v1/copilot/search
  def search
    query = params[:query]

    # Fast exit if the user submitted an empty string
    return render json: { results: [] }, status: :ok if query.blank?

    begin
      # 1. Ask Python to translate the text into mathematical coordinates
      query_vector = fetch_query_embedding(query)

      # 2. Execute the HNSW Nearest Neighbor search using the scope we built in Phase 1
      # We limit to 20 to keep the UI snappy and relevant
      assets = Asset.nearest_to_vector(query_vector).limit(20)

      # 3. Format the response for the React UI
      render json: {
        results: assets.map do |asset|
          {
            id: asset.id,
            original_filename: asset.original_filename,
            file_url: asset.file_url, # Assuming a helper that points to your AWS S3 bucket
            properties: asset.properties,
          }
        end,
      }, status: :ok
    rescue => e
      Rails.logger.error("Semantic Search Failed: #{e.message}")
      render json: { error: "Failed to process semantic query." }, status: :internal_server_error
    end
  end

  private

  def fetch_query_embedding(text)
    uri = URI.parse("http://localhost:8000/api/embed_query")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request.body = { text: text }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end

    raise "AI Gateway Error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)["vector"]
  end
end
