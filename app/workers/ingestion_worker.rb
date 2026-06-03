require 'net/http'
require 'uri'

class IngestionWorker
  include Sidekiq::Worker
  sidekiq_options retry: 3, queue: 'ingestion'

  def perform(connector_id, payload_json)
    connector = SystemConnector.find_by(id: connector_id)
    return unless connector && connector.status == 'active'

    payload = JSON.parse(payload_json)

    # Extract baseline data (adjust these keys based on your AEM/S3 actual payload structures)
    filename = payload.dig('asset', 'name') || "unknown_file_#{Time.now.to_i}"
    metadata = payload.dig('asset', 'properties') || {}

    # Check if the architect enabled the AI TDM pipeline for this specific connector
    if connector.tdm_sanitation?
      evaluation = evaluate_via_ai_gateway(filename, metadata)

      if evaluation['approved']
        ingest_clean_asset!(connector, filename, metadata, payload)
      else
        quarantine_dirty_asset!(connector, payload, evaluation['reason'])
      end
    else
      # TDM is bypassed; ingest directly (legacy behavior)
      ingest_clean_asset!(connector, filename, metadata, payload)
    end
  end

  private

  def evaluate_via_ai_gateway(filename, metadata)
    uri = URI.parse("http://localhost:8000/api/tdm/evaluate")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request.body = { filename: filename, metadata: metadata }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end

    raise "AI Gateway Error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  rescue => e
    Rails.logger.error("TDM Gateway Unreachable: #{e.message}")
    # Fail closed to protect the core system
    { 'approved' => false, 'reason' => 'AI Gateway Timeout/Error' }
  end

  def ingest_clean_asset!(connector, filename, metadata, full_payload)
    # Create the asset in the primary ecosystem
    Asset.create!(
      original_filename: filename,
      properties: metadata,
    # Map other critical fields like URL, file_size, etc. from the payload
      )

    # Update metrics
    connector.increment!(:assets_imported)
    connector.update!(last_sync: Time.current)
  end

  def quarantine_dirty_asset!(connector, full_payload, reason)
    # Isolate the failure
    QuarantinedAsset.create!(
      system_connector: connector,
      original_payload: full_payload,
      rejection_reason: reason
    )
    Rails.logger.warn("Asset Quarantined from Connector #{connector.id}: #{reason}")
  end
end