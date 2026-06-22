require 'net/http'
require 'uri'

# MigrationTransformWorker
# ─────────────────────────────────────────────────────────────────────────────
# Processes a single staged IngestionItem through the AI metadata normalization
# pipeline. Called in parallel after ExtractionWorker stages items.
#
# Queue: 'metadata' (low priority — heavy AI work, won't delay mailers or workflows)
# Retry: 3 times with exponential backoff
class MigrationTransformWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'metadata', retry: 3

  def perform(item_id)
    item = IngestionItem.find_by(id: item_id)
    return unless item
    return if item.committed? || item.rejected?

    batch = item.ingestion_batch
    return unless batch

    begin
      # 1. Skip duplicates — they were flagged at extraction time
      if item.flagged_duplicate?
        item.update!(status: :rejected, error_log: 'Deduplication: exact hash match found in live DAM.')
        batch.increment!(:duplicate_count)
        return
      end

      # 2. Normalize legacy metadata via AI Gateway
      normalized = normalize_metadata(item)

      # 3. Save the cleaned, structured metadata
      item.update!(
        clean_properties: normalized,
        status: :ready_for_import
      )

      Rails.logger.info("[MigrationTransform] Item #{item.id} normalized: #{normalized['title']}")

    rescue => e
      Rails.logger.error("[MigrationTransform] Failed for item #{item.id}: #{e.message}")
      item.update!(status: :flagged_error, error_log: e.message)
      batch.increment!(:error_count)
      raise e  # Re-raise for Sidekiq retry
    ensure
      batch.calculate_progress!
      transition_batch_if_complete!(batch)
    end
  end

  private

  # ─── AI Metadata Normalization ─────────────────────────────────────────────
  # Calls the Python FastAPI gateway to extract a clean, structured schema
  # from the legacy metadata blob. Falls back to rule-based normalization.
  def normalize_metadata(item)
    raw = item.legacy_metadata || {}

    # Attempt AI normalization via gateway
    ai_result = call_ai_gateway(item.original_filename, raw)
    return ai_result if ai_result.present?

    # Rule-based fallback: map common legacy field names to canonical schema
    fallback_normalize(item.original_filename, raw)
  end

  def call_ai_gateway(filename, metadata)
    uri     = URI.parse("#{ai_gateway_url}/api/tdm/normalize")
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    request.body = { filename: filename, metadata: metadata }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 10, read_timeout: 30) do |http|
      http.request(request)
    end

    return nil unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  rescue => e
    Rails.logger.warn("[MigrationTransform] AI Gateway unavailable: #{e.message}. Using fallback normalization.")
    nil
  end

  # Common legacy field aliases → canonical DAM schema
  FIELD_MAP = {
    # Title variants
    'dc:title' => 'title', 'name' => 'title', 'filename' => 'title', 'asset_name' => 'title',
    # Description variants
    'dc:description' => 'description', 'caption' => 'description', 'abstract' => 'description',
    # Tags variants
    'dc:subject' => 'tags', 'keywords' => 'tags', 'tag' => 'tags', 'cq:tags' => 'tags',
    # Creator
    'dc:creator' => 'author', 'creator' => 'author', 'xmp_creator' => 'author',
    # Dates
    'dc:created' => 'created', 'jcr:created' => 'created', 'creation_date' => 'created',
    # Media type
    'dam:mimeType' => 'content_type', 'contentType' => 'content_type', 'mime_type' => 'content_type',
    # Campaign / project
    'campaign_name' => 'campaign', 'project' => 'campaign',
    # Usage rights
    'xmpRights:usageTerms' => 'usage_terms', 'usage_terms' => 'usage_terms',
    'xmpRights:expiry' => 'license_expires_at', 'license_expires_at' => 'license_expires_at'
  }.freeze

  def fallback_normalize(filename, raw)
    result = {}
    raw.each do |key, value|
      canonical_key = FIELD_MAP[key.to_s] || key.to_s.parameterize.underscore
      result[canonical_key] = value
    end

    # Ensure title is always set
    result['title'] ||= File.basename(filename.to_s, '.*').titleize
    # Normalize tags to array
    result['tags'] = Array(result['tags']).flatten.map(&:to_s).uniq
    result
  end

  def transition_batch_if_complete!(batch)
    return unless batch.extracting? || batch.transforming?

    total      = batch.total_count.to_i
    processed  = batch.ingestion_items.where(status: [:ready_for_import, :rejected]).count

    return unless processed >= total && total > 0

    batch.review_needed!
    Rails.logger.info("[MigrationTransform] Batch #{batch.id} → review_needed (#{processed}/#{total} items processed)")
  end

  def ai_gateway_url
    ENV.fetch('AI_GATEWAY_URL', 'http://localhost:8000')
  end
end

