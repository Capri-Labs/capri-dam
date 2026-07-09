require "digest"

class ExtractionWorker
  include Sidekiq::Worker

  # Using the 'ingest' queue to group heavy ETL tasks
  # Sidekiq handles exponential backoff automatically on the 3 retries
  sidekiq_options queue: "ingest", retry: 3

  def perform(batch_id)
    batch = IngestionBatch.find_by(id: batch_id)
    return unless batch && (batch.extracting? || batch.initializing?)

    batch.update!(status: :extracting) if batch.initializing?

    # Using the new app/adapters/ingestion/ directory structure
    adapter = IngestionAdapters::Factory.build(batch)

    process_chunk(batch, adapter)
  end

  private

  def process_chunk(batch, adapter)
    # 1. Fetch the next paginated chunk using the legacy system's cursor
    cursor = batch.respond_to?(:last_cursor) ? batch.last_cursor : nil
    result = adapter.fetch_next_chunk(cursor)

    result[:files].each do |file_data|
      # Idempotency check: Skip if we already staged this file in a prior failed attempt
      next if batch.ingestion_items.exists?(original_filename: file_data[:identifier])

      process_single_file(batch, adapter, file_data)
    end

    # 2. Update the batch state
    update_attributes = {}
    update_attributes[:last_cursor] = result[:next_cursor] if batch.respond_to?(:last_cursor)
    batch.update!(update_attributes) if update_attributes.any?
    batch.calculate_progress!

    # 3. Recursion via Sidekiq
    if result[:has_more]
      ExtractionWorker.perform_async(batch.id)
    else
      batch.update!(status: :transforming) # Hand off to the AI phase
    end
  end

  def process_single_file(batch, adapter, file_data)
    sha256 = Digest::SHA256.new

    # 4. Stream and hash in real-time
    temp_file_path = adapter.download_and_stream(file_data[:identifier]) do |chunk|
      sha256.update(chunk)
    end

    final_hash = sha256.hexdigest

    # Edge-Level Deduplication
    status = if Asset.column_names.include?("file_hash")
      Asset.exists?(file_hash: final_hash) ? :flagged_duplicate : :pending
    else
      :pending
    end

    item = batch.ingestion_items.create!(
      original_filename: file_data[:identifier],
      file_size: file_data[:size],
      file_hash: final_hash,
      legacy_metadata: file_data[:metadata] || {},
      full_metadata: file_data[:raw_metadata] || {},
      status: status
    )

    # 5. Broadcast to the AI Gateway if it needs metadata transformation, and
    # enqueue the normalization worker that actually advances the item's
    # state. (The Redis broadcast alone is a fire-and-forget notification for
    # an external listener — MigrationTransformWorker is what performs the
    # local AI-normalize-with-rule-based-fallback step and flips the item to
    # ready_for_import/rejected; without enqueuing it here every staged item
    # — including duplicates, which MigrationTransformWorker rejects — stays
    # stuck forever and the batch never reaches review_needed.)
    #
    # NOTE: capture the pre-broadcast state first — broadcast_to_ai_gateway
    # mutates `item.status` to :ai_processing in place, so checking
    # item.pending? *after* calling it would always be false and silently
    # skip the enqueue below.
    needs_transform = item.pending? || item.flagged_duplicate?
    broadcast_to_ai_gateway(item) if item.pending?
    MigrationTransformWorker.perform_async(item.id) if needs_transform

    # Cleanup the temp file from the Sidekiq server immediately
    File.delete(temp_file_path) if File.exist?(temp_file_path)
  end

  def broadcast_to_ai_gateway(item)
    payload = {
      event: "ingestion.item.staged",
      item_id: item.id,
      item_uuid: item.respond_to?(:uuid) ? item.uuid : item.id,
    }.to_json

    # Dispatching the event so the Python MCP Gateway can pick it up.
    # Redis.current was removed in redis-rb 5.x — use an explicit connection
    # instead (matches the pattern used elsewhere in the codebase, e.g.
    # SearchCache, RedisTokenManager, Asset).
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    redis.publish("ai_gateway_events", payload)

    item.update!(status: :ai_processing)
  end
end
