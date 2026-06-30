# Sidekiq worker that performs a **full repository scan** to find all existing
# assets sharing the same SHA-256 checksum and creates the corresponding
# {DuplicateGroup} records.
#
# This is the complement to {DuplicateDetectionWorker}: that worker handles
# *new* uploads in real-time; this worker back-fills the entire repository
# (useful when duplicate detection is first enabled, or run on-demand by an
# admin after importing a batch of assets).
#
# == Version-awareness rule
#
# An asset that has been updated multiple times will have multiple {AssetVersion}
# rows, some of which may share the same SHA-256 (e.g. the file was restored to
# a previous version).  These are **not** duplicates — they are the version
# history of a single asset.
#
# The duplicate definition is:
#
#   Two or more *different assets* (distinct +asset_id+ values) whose active
#   or any historical version contains the same +checksum_sha256+.
#
# The worker enforces this by grouping on +DISTINCT asset_id+ in SQL.
#
# == Algorithm
#
# 1. Guard: skip if detection is disabled or a scan is already running.
# 2. Mark status = "running" in Settings.
# 3. Query +asset_versions+ grouped by checksum → keep only checksums that
#    appear for ≥ 2 different, non-deleted assets.
# 4. Process groups in batches of {BATCH_SIZE}:
#    a. Find-or-create a +pending+ {DuplicateGroup} for the checksum.
#    b. Register all member assets via {DuplicateGroupAsset}.
#    c. Mark the earliest-created asset as +is_original: true+.
#    d. Update +total_count+.
# 5. Mark status = "completed", record +last_scan_at+ and stats.
# 6. If an error escapes: mark status = "failed" and re-raise for Sidekiq retry.
#
# == Queue & retry policy
#
# * Queue:   +duplicate_detection+
# * Retries: 1  (avoid duplicate groups being partially created twice)
#
# == Concurrency guard
#
# Only one scan may run at a time.  If a scan is already "running" when
# +perform+ is called, the new job exits immediately.  The Setting key
# +duplicate_manager_scan_status+ acts as the distributed lock.
#
# @see DuplicateDetectionWorker  (per-upload real-time detection)
# @see DuplicateDetectionService
# @see DuplicateGroup
class DuplicateRepositoryScanWorker
  include Sidekiq::Worker
  sidekiq_options queue: "duplicate_detection", retry: 1

  # Number of duplicate checksums processed per transaction slice.
  BATCH_SIZE = 100

  # ── Entry point ─────────────────────────────────────────────────────────────

  # @return [void]
  def perform
    unless detection_enabled?
      Rails.logger.info "[DuplicateRepositoryScanWorker] Detection is disabled — skipping."
      return
    end

    if scan_running?
      Rails.logger.info "[DuplicateRepositoryScanWorker] Scan already running — skipping duplicate job."
      return
    end

    mark_status("running", processed: 0, total: 0, started_at: Time.current.iso8601)

    duplicate_rows = fetch_duplicate_checksums
    total          = duplicate_rows.size

    Rails.logger.info(
      "[DuplicateRepositoryScanWorker] #{total} checksum(s) with multiple distinct assets found."
    )

    processed = 0

    duplicate_rows.each_slice(BATCH_SIZE) do |batch|
      batch.each do |row|
        process_checksum_group(row[:checksum], row[:asset_ids])
        processed += 1
      end

      # Update progress every BATCH_SIZE items.
      mark_progress(processed, total)
      Rails.logger.info "[DuplicateRepositoryScanWorker] Progress: #{processed}/#{total}"
    end

    mark_status("completed",
                processed:    processed,
                total:        total,
                completed_at: Time.current.iso8601)

    Setting.set("duplicate_manager_last_scan_at", Time.current.iso8601)

    Rails.logger.info(
      "[DuplicateRepositoryScanWorker] Scan complete — #{processed} duplicate group(s) processed."
    )
  rescue StandardError => e
    mark_status("failed",
                processed: 0,
                total:     0,
                error:     "#{e.class}: #{e.message}")

    Rails.logger.error(
      "[DuplicateRepositoryScanWorker] Scan failed: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    )
    raise
  end

  private

  # ── SQL scan ────────────────────────────────────────────────────────────────

  # Returns rows for checksums that appear across ≥ 2 distinct, non-deleted
  # assets.  Multiple versions of the *same* asset collapse into one via
  # +DISTINCT asset_id+.
  #
  # @return [Array<Hash>] +[ { checksum:, asset_ids:, asset_count: }, … ]+
  def fetch_duplicate_checksums
    sql = <<~SQL
      SELECT
        av.properties->>'checksum_sha256'                     AS checksum,
        string_agg(DISTINCT av.asset_id::text, ',')           AS asset_ids,
        COUNT(DISTINCT av.asset_id)                           AS asset_count
      FROM asset_versions av
      INNER JOIN assets a ON a.id = av.asset_id
      WHERE av.properties->>'checksum_sha256' IS NOT NULL
        AND av.properties->>'checksum_sha256' <> ''
        AND a.deleted_at IS NULL
      GROUP BY av.properties->>'checksum_sha256'
      HAVING COUNT(DISTINCT av.asset_id) > 1
      ORDER BY asset_count DESC, checksum
    SQL

    ActiveRecord::Base.connection.exec_query(sql).map do |row|
      {
        checksum:    row["checksum"],
        asset_ids:   row["asset_ids"].to_s.split(",").map(&:strip).reject(&:empty?),
        asset_count: row["asset_count"].to_i,
      }
    end
  end

  # ── Group processing ─────────────────────────────────────────────────────────

  # Creates or updates a pending {DuplicateGroup} for +checksum+ and registers
  # all +asset_ids+ as members.
  #
  # @param checksum  [String]        SHA-256 hex digest
  # @param asset_ids [Array<String>] UUID strings
  # @return [void]
  def process_checksum_group(checksum, asset_ids)
    return if asset_ids.size < 2

    ActiveRecord::Base.transaction do
      # The checksum column has a unique index, so only one group per checksum
      # can exist at a time.  Find by checksum alone and reopen it if resolved.
      group = DuplicateGroup.find_or_initialize_by(checksum: checksum)
      if group.new_record?
        group.status = "pending"
        group.save!
      elsif group.status != "pending"
        group.update!(
          status:            "pending",
          resolved_at:       nil,
          resolution_action: nil,
          resolved_by_id:    nil,
        )
      end

      asset_ids.each { |aid| safe_register_member(group, aid) }

      mark_original(group)
      group.update!(total_count: group.duplicate_group_assets.count)
    end
  rescue StandardError => e
    Rails.logger.warn(
      "[DuplicateRepositoryScanWorker] Skipping checksum #{checksum.first(16)}…: #{e.message}"
    )
  end

  # Adds a member to the group if not already registered.
  #
  # @param group    [DuplicateGroup]
  # @param asset_id [String] UUID
  # @return [void]
  def safe_register_member(group, asset_id)
    return if DuplicateGroupAsset.exists?(
      duplicate_group_id: group.id,
      asset_id:           asset_id
    )

    DuplicateGroupAsset.create!(
      duplicate_group_id: group.id,
      asset_id:           asset_id,
      is_original:        false
    )
  rescue ActiveRecord::RecordNotUnique
    # Concurrent insert — safe to ignore.
  end

  # Sets +is_original: true+ on the oldest (by +created_at+) member asset.
  #
  # @param group [DuplicateGroup]
  # @return [void]
  def mark_original(group)
    oldest = Asset
      .where(id: group.duplicate_group_assets.select(:asset_id))
      .order(:created_at)
      .first

    return unless oldest

    group.duplicate_group_assets.update_all(is_original: false)
    group.duplicate_group_assets
         .where(asset_id: oldest.id)
         .update_all(is_original: true)
  end

  # ── Status helpers ───────────────────────────────────────────────────────────

  # @return [Boolean]
  def detection_enabled?
    val = Setting.get("duplicate_manager_enabled")
    val == true || val == "true"
  end

  # @return [Boolean]
  def scan_running?
    Setting.get("duplicate_manager_scan_status") == "running"
  end

  # Persists scan status + progress atomically.
  #
  # @param status  [String]
  # @param kwargs  [Hash]
  # @return [void]
  def mark_status(status, **kwargs)
    Setting.set("duplicate_manager_scan_status", status)
    mark_progress(kwargs[:processed] || 0, kwargs[:total] || 0,
                  started_at:   kwargs[:started_at],
                  completed_at: kwargs[:completed_at],
                  error:        kwargs[:error])
  end

  # @param processed  [Integer]
  # @param total      [Integer]
  # @param kwargs     [Hash]
  # @return [void]
  def mark_progress(processed, total, **kwargs)
    progress = {
      processed:  processed,
      total:      total,
      updated_at: Time.current.iso8601,
    }
    %i[started_at completed_at error].each do |key|
      progress[key] = kwargs[key] if kwargs.key?(key)
    end
    Setting.set("duplicate_manager_scan_progress", progress)
  end
end
