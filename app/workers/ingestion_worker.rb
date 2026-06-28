# Sidekiq worker that ingests an asset payload received from an external
# {SystemConnector} (migration source or webhook).
#
# == Processing pipeline
#
# 1. **Rate limiting** — a per-connector Redis counter enforces the connector's
#    +rps_limit+.  Jobs that exceed the limit re-schedule themselves 5 seconds
#    later rather than blocking a thread.
#
# 2. **TDM sanitation** (when +connector.tdm_sanitation?+ is true) — the asset
#    is evaluated by the AI gateway (+POST /api/tdm/evaluate+).  Approved assets
#    continue to ingestion; rejected assets are quarantined in
#    {QuarantinedAsset}.
#
# 3. **Clean ingest** — a vector embedding is generated for the asset's
#    filename + metadata text.  The {Asset} row is created inside a transaction
#    and {SmartCollectionRouterWorker} is enqueued to route it into the
#    appropriate smart collections.
#
# == Queue & throttle policy
#
# * Queue:      +ingestion+
# * Retries:    3
# * Concurrency ceiling: 10 simultaneous jobs (via +Sidekiq::Throttled+)
# * Per-connector rate: configurable via +connector.rps_limit+ (default 5 RPS)
#
# @see SystemConnector
# @see QuarantinedAsset
# @see SmartCollectionRouterWorker
require "net/http"
require "uri"

class IngestionWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Worker

  sidekiq_options retry: 3, queue: "ingest"

  # Hard concurrency ceiling shared across all instances of this worker.
  sidekiq_throttle(concurrency: { limit: 10 })

  # Ingests a single asset payload from the specified connector.
  #
  # @param connector_id  [Integer] the database ID of the {SystemConnector}
  # @param payload_json  [String]  JSON-encoded asset payload with at least
  #   +asset.name+ and optionally +asset.properties+
  # @return [void]
  def perform(connector_id, payload_json)
    connector = SystemConnector.find_by(id: connector_id)
    return unless connector && connector.status == "active"

    if rate_limited?(connector)
      IngestionWorker.perform_in(5.seconds, connector_id, payload_json)
      return
    end

    payload  = JSON.parse(payload_json)
    filename = payload.dig("asset", "name") || "unknown_file_#{Time.now.to_i}"
    metadata = payload.dig("asset", "properties") || {}

    if connector.tdm_sanitation?
      evaluation = evaluate_via_ai_gateway(filename, metadata)

      if evaluation["approved"]
        ingest_clean_asset!(connector, filename, metadata, payload)
      else
        quarantine_dirty_asset!(connector, payload, evaluation["reason"])
      end
    else
      ingest_clean_asset!(connector, filename, metadata, payload)
    end
  end

  private

  # Returns +true+ when the connector has exceeded its per-second rate limit.
  #
  # Uses a Redis counter with a 1-second TTL.  The check and increment are
  # wrapped in a +MULTI/EXEC+ block to be thread-safe.
  #
  # @param connector [SystemConnector]
  # @return [Boolean]
  def rate_limited?(connector)
    key        = "throttle:connector:#{connector.id}"
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

  # Calls the external AI gateway to determine whether an asset is safe to ingest.
  #
  # Returns an approval hash with at minimum an +'approved'+ boolean and a
  # +'reason'+ string.  Falls back to a +false+ approval on network errors so
  # that gateway unavailability quarantines assets rather than crashing.
  #
  # @param filename [String]
  # @param metadata [Hash]
  # @return [Hash] e.g. +{ 'approved' => true }+ or
  #   +{ 'approved' => false, 'reason' => '...' }+
  def evaluate_via_ai_gateway(filename, metadata)
    uri     = URI.parse("http://localhost:8000/api/tdm/evaluate")
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    request.body = { filename: filename, metadata: metadata }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
    raise "AI Gateway Error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue => e
    Rails.logger.error("TDM Gateway Unreachable: #{e.message}")
    { "approved" => false, "reason" => "AI Gateway Timeout/Error" }
  end

  # Fetches a vector embedding for the given text from the AI gateway.
  #
  # @param text_to_embed [String] the concatenated semantic string
  # @return [Array<Float>, nil] the embedding vector, or +nil+ on failure
  def fetch_vector_embedding(text_to_embed)
    uri     = URI.parse("http://localhost:8000/api/embed_query")
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    request.body = { text: text_to_embed }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)["vector"]
  rescue => e
    Rails.logger.warn("Vector Generation Failed: #{e.message}")
    nil
  end

  # Creates an {Asset} row for a TDM-approved payload, generates a vector
  # embedding, and enqueues smart-collection routing.
  #
  # All database writes are wrapped in a transaction for consistency.
  #
  # @param connector    [SystemConnector]
  # @param filename     [String]
  # @param metadata     [Hash]
  # @param full_payload [Hash] the raw parsed payload (stored for reference)
  # @return [void]
  def ingest_clean_asset!(connector, filename, metadata, full_payload)
    semantic_string = "#{filename} " + metadata.values.join(" ")
    vector_array    = fetch_vector_embedding(semantic_string)

    ActiveRecord::Base.transaction do
      asset = Asset.create!(
        original_filename: filename,
        properties:        metadata,
        vector_embedding:  vector_array
      )

      connector.increment!(:assets_imported)
      connector.update!(last_sync: Time.current)

      SmartCollectionRouterWorker.perform_async(asset.id) if asset.vector_embedding.present?
    end
  end

  # Creates a {QuarantinedAsset} record for a TDM-rejected payload.
  #
  # @param connector    [SystemConnector]
  # @param full_payload [Hash]   the raw parsed payload
  # @param reason       [String] the rejection reason from the AI gateway
  # @return [void]
  def quarantine_dirty_asset!(connector, full_payload, reason)
    QuarantinedAsset.create!(
      system_connector: connector,
      original_payload: full_payload,
      rejection_reason: reason
    )
    Rails.logger.warn("Asset Quarantined from Connector #{connector.id}: #{reason}")
  end
end
