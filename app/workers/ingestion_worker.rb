require 'net/http'
require 'uri'

class IngestionWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Worker

  sidekiq_options retry: 3, queue: 'ingestion'

  # We keep the base gem throttle as a hard ceiling,
  # while the dynamic Redis logic below handles per-connector limits.
  sidekiq_throttle(
    concurrency: { limit: 10 }
  )

  def perform(connector_id, payload_json)
    connector = SystemConnector.find_by(id: connector_id)
    return unless connector && connector.status == 'active'

    if rate_limited?(connector)
      IngestionWorker.perform_in(5.seconds, connector_id, payload_json)
      return
    end

    payload = JSON.parse(payload_json)

    filename = payload.dig('asset', 'name') || "unknown_file_#{Time.now.to_i}"
    metadata = payload.dig('asset', 'properties') || {}

    if connector.tdm_sanitation?
      evaluation = evaluate_via_ai_gateway(filename, metadata)

      if evaluation['approved']
        ingest_clean_asset!(connector, filename, metadata, payload)
      else
        quarantine_dirty_asset!(connector, payload, evaluation['reason'])
      end
    else
      # TDM bypassed, but we still need a vector for Smart Collections
      ingest_clean_asset!(connector, filename, metadata, payload)
    end
  end

  private

  def rate_limited?(connector)
    key = "throttle:connector:#{connector.id}"

    #  REFINEMENT 1: Use Sidekiq's thread-safe Redis pool
    is_limited = false

    Sidekiq.redis do |redis|
      count = redis.get(key).to_i
      if count >= (connector.rps_limit || 5)
        is_limited = true
      else
        redis.multi do |multi|
          multi.incr(key)
          multi.expire(key, 1)
        end
      end
    end

    is_limited
  end

  def evaluate_via_ai_gateway(filename, metadata)
    uri = URI.parse("http://localhost:8000/api/tdm/evaluate")
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    request.body = { filename: filename, metadata: metadata }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
    raise "AI Gateway Error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue => e
    Rails.logger.error("TDM Gateway Unreachable: #{e.message}")
    { 'approved' => false, 'reason' => 'AI Gateway Timeout/Error' }
  end

  #  REFINEMENT 2: Fetch the vector embedding for Semantic Routing
  def fetch_vector_embedding(text_to_embed)
    uri = URI.parse("http://localhost:8000/api/embed_query")
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    request.body = { text: text_to_embed }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)['vector']
  rescue => e
    Rails.logger.warn("Vector Generation Failed: #{e.message}")
    nil
  end

  def ingest_clean_asset!(connector, filename, metadata, full_payload)
    # Generate the vector based on filename + rich metadata
    semantic_string = "#{filename} " + metadata.values.join(" ")
    vector_array = fetch_vector_embedding(semantic_string)

    # Wrap in a transaction to ensure database consistency
    ActiveRecord::Base.transaction do
      asset = Asset.create!(
        original_filename: filename,
        properties: metadata,
        vector_embedding: vector_array
      # Map other critical fields like URL, file_size, etc.
      )

      connector.increment!(:assets_imported)
      connector.update!(last_sync: Time.current)

      #  REFINEMENT 3: Hand off to the Smart Router
      if asset.vector_embedding.present?
        SmartCollectionRouterWorker.perform_async(asset.id)
      end
    end
  end

  def quarantine_dirty_asset!(connector, full_payload, reason)
    QuarantinedAsset.create!(
      system_connector: connector,
      original_payload: full_payload,
      rejection_reason: reason
    )
    Rails.logger.warn("Asset Quarantined from Connector #{connector.id}: #{reason}")
  end
end