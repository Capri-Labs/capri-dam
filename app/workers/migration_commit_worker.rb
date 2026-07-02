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

  def perform(batch_id, cursor = 0)
    batch = IngestionBatch.find_by(id: batch_id)
    return unless batch
    return unless batch.review_needed? || batch.committed?

    batch.update!(status: :committed, started_at: batch.started_at || Time.current) if batch.review_needed?

    items = batch.ingestion_items
                 .where(status: :ready_for_import)
                 .order(:id)
                 .limit(COMMIT_CHUNK)
                 .offset(cursor)

    if items.empty?
      finalize_batch!(batch)
      return
    end

    items.each do |item|
      commit_item!(batch, item)
    end

    # Recurse via Sidekiq to process the next chunk (avoids memory bloat on huge batches)
    MigrationCommitWorker.perform_async(batch_id, cursor + COMMIT_CHUNK)
  end

  private

  def commit_item!(batch, item)
    props   = item.clean_properties.presence || {}
    folder  = resolve_target_folder(batch, props)

    ActiveRecord::Base.transaction do
      # Create the canonical Asset record
      asset = Asset.create!(
        title:     props["title"].presence || File.basename(item.original_filename, ".*").titleize,
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
  rescue => e
    Rails.logger.error("[MigrationCommit] Failed to commit item #{item.id}: #{e.message}")
    item.update!(status: :flagged_error, error_log: e.message)
    batch.increment!(:error_count)
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
