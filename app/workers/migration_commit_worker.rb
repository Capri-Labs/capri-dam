# MigrationCommitWorker
# ─────────────────────────────────────────────────────────────────────────────
# Commits all approved IngestionItems from a batch into the live Asset table.
# Called once when a human admin clicks "Approve & Commit Batch" in the UI.
# Processes items in parallel mini-batches, then triggers the report worker.
#
# Queue: 'ingest'  (heavy I/O — low priority)
# Retry: 2 times
class MigrationCommitWorker
  include Sidekiq::Worker
  sidekiq_options queue: "ingest", retry: 2

  COMMIT_CHUNK = 50  # process this many items per job call

  def perform(batch_id)
    batch = IngestionBatch.find_by(id: batch_id)
    return unless batch
    return unless batch.review_needed? || batch.committed?

    batch.update!(status: :committed, started_at: batch.started_at || Time.current) if batch.review_needed?

    # NOTE: no OFFSET here — the WHERE clause naturally shrinks as items get
    # committed (commit_item! flips their status away from ready_for_import),
    # so always re-querying "the next COMMIT_CHUNK still ready_for_import"
    # is correct. Using an offset here was a real bug: as each chunk commits
    # and removes itself from the ready_for_import pool, advancing the
    # offset on the next call would skip over the next uncommitted chunk
    # (the pool shifts under you), silently leaving roughly half of every
    # large batch stuck at ready_for_import forever while the batch still
    # reported "committed".
    items = batch.ingestion_items
                 .where(status: :ready_for_import)
                 .order(:id)
                 .limit(COMMIT_CHUNK)

    if items.empty?
      finalize_batch!(batch)
      return
    end

    items.each do |item|
      commit_item!(batch, item)
    end

    # Recurse via Sidekiq to process the next chunk (avoids memory bloat on huge batches)
    MigrationCommitWorker.perform_async(batch_id)
  end

  private

  def commit_item!(batch, item)
    props   = item.clean_properties.presence || {}
    folder  = resolve_target_folder(batch, props)

    # Re-fetch the original binary from the source system now. ExtractionWorker
    # only streamed the file through a SHA256 digest for hashing/dedup and
    # discarded the tempfile — nothing before this point has ever persisted
    # the actual asset content. AssetProcessorWorker (enqueued below, after
    # the transaction commits) is what stores the real binary, generates
    # thumbnails/previews, extracts binary-level metadata, and flips the
    # asset's status from pending to ready. Without this, committed assets
    # are just metadata records with no file behind them, stuck at "pending"
    # forever.
    adapter      = IngestionAdapters::Factory.build(batch)
    staging_path = adapter.download_and_stream(item.original_filename)
    version      = nil

    ActiveRecord::Base.transaction do
      # Create the canonical Asset record
      asset = Asset.create!(
        title:     props["title"].presence || File.basename(item.original_filename),
        user_id:   batch.initiated_by_id || User.first&.id,
        folder:    folder,
        status:    :pending,
        uuid:      SecureRandom.uuid,
        properties: {
          original_filename: item.original_filename,
          description:       props["description"],
          alt_text:          props["alt_text"] || props["description"],
          usage_terms:       props["usage_terms"] || "Internal Use Only",
          tags:              Array(props["tags"]),
          author:            props["author"],
          campaign:          props["campaign"],
          license_expires_at: props["license_expires_at"],
          migrated_from:     batch.source_type,
          migration_batch_id: batch.id.to_s,
          content_type:      props["content_type"],
        }.compact
      )

      # Create the initial version record
      version = asset.asset_versions.create!(
        version_number: 1,
        action_type:    "migration_import",
        created_by_id:  batch.initiated_by_id,
        properties: {
          source_identifier: item.original_filename,
          file_hash:         item.file_hash,
          file_size:         item.file_size,
          legacy_metadata:   item.legacy_metadata,
          # The raw jcr:content/metadata.json payload fetched at extraction
          # time (present only when the batch had "Migrate Metadata"
          # enabled) — committed directly onto the version record so
          # operators can audit exactly what full metadata was migrated for
          # this asset, without re-deriving it from the (already-deleted)
          # IngestionItem.
          full_metadata:     item.full_metadata,
        }
      )

      asset.update!(active_version_id: version.id)

      # Mark item as committed and link to new asset
      item.update!(status: :committed)
      batch.increment!(:committed_count)

      # Trigger AI embedding after commit
      asset.send(:broadcast_for_embedding) if asset.respond_to?(:broadcast_for_embedding, true)

      Rails.logger.info("[MigrationCommit] Asset #{asset.uuid} committed from item #{item.id}")
    end

    # Enqueue *after* the transaction commits — enqueuing inside an open
    # transaction risks the Sidekiq job (picked up by a separate worker
    # process) looking up the AssetVersion before this transaction's writes
    # are actually visible to other DB connections.
    AssetProcessorWorker.perform_async(version.id, staging_path)
  rescue => e
    Rails.logger.error("[MigrationCommit] Failed to commit item #{item.id}: #{e.message}")
    item.update!(status: :flagged_error, error_log: e.message)
    batch.increment!(:error_count)
    File.delete(staging_path) if staging_path && File.exist?(staging_path)
  end

  def finalize_batch!(batch)
    batch.update!(
      status:       :committed,
      completed_at: Time.current
    )

    Rails.logger.info(
      "[MigrationCommit] Batch #{batch.id} fully committed — " \
      "#{batch.committed_count} assets, #{batch.duplicate_count} duplicates blocked, #{batch.error_count} errors."
    )

    # Fire the report + notification worker (single batch-level email)
    MigrationReportWorker.perform_async(batch.id)
  end

  def resolve_target_folder(batch, props)
    # An explicit destination folder chosen in the migration wizard always wins.
    return batch.destination_folder if batch.destination_folder.present?

    # Otherwise try to map the asset's source campaign/folder to an existing DAM
    # folder, creating a migration staging folder if no match is found.
    folder_name = props["campaign"].presence || "Migration — #{batch.source_type.upcase} — #{batch.created_at.strftime("%Y-%m-%d")}"

    Folder.find_or_create_by!(
      name:    folder_name,
      user_id: batch.initiated_by_id || User.first&.id
    )
  rescue => e
    Rails.logger.warn("[MigrationCommit] Could not resolve folder: #{e.message}. Asset will be in root.")
    nil
  end
end
