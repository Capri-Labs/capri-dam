# Service object encapsulating the logic for permanently purging expired
# soft-deleted assets and folders from the Recycle Bin.
#
# == Enterprise concerns handled
#
# 1. **Active workflow detection** — assets with a live workflow can be
#    configured to either be *skipped* (default) or have their workflows
#    *force-terminated* before deletion.
#
# 2. **Reference integrity cleanup** — before hard-deleting an asset the
#    service removes all satellite records in the correct order:
#    +DuplicateGroupAsset+ (and resolves now-singleton groups),
#    +CollectionAsset+, physical storage files + ActiveStorage blobs.
#    Everything else (versions, embedding, workflow instances, tasks) is
#    handled by +dependent: :destroy+ cascades on the Asset model.
#
# 3. **Error isolation** — each item is processed in its own +rescue+ block.
#    A failure on one item is logged and counted but never stops the batch.
#
# 4. **Folder safety** — a trashed folder is only hard-deleted after all its
#    contents (including nested sub-folders) have already been removed.  A
#    folder that still contains active (non-trashed) records is *skipped* to
#    avoid orphaning live assets.
#
# 5. **Audit trail preservation** — +AuditLog+ rows are deliberately left in
#    place.  They are compliance records and must survive asset deletion.
#
# == Usage
#
#   result = BinPurgeService.new(
#     retention_days:    30,
#     workflow_behavior: "skip",   # or "force_terminate"
#     batch_size:        50,
#   ).call
#
#   result.deleted   # => Integer
#   result.skipped   # => Integer
#   result.failed    # => Integer
#   result.skipped_items  # => Array<Hash> { id, type, title, reason }
#   result.errors         # => Array<Hash> { id, type, title, message }
#
class BinPurgeService
  # Workflow instance statuses that indicate the asset is still actively
  # being reviewed and should not be silently destroyed.
  ACTIVE_WORKFLOW_STATUSES = %w[pending in_progress in_review].freeze

  # Value object returned to the caller.
  Result = Struct.new(
    :deleted, :skipped, :failed,
    :skipped_items, :errors,
    :storage_reclaimed_bytes,
    keyword_init: true
  )

  # @param retention_days    [Integer] items deleted more than this many days
  #   ago are eligible for hard purge
  # @param workflow_behavior [String]  +"skip"+ or +"force_terminate"+
  # @param batch_size        [Integer] find_each batch size
  def initialize(retention_days: 30, workflow_behavior: "skip", batch_size: 50)
    @retention_days    = retention_days.to_i
    @workflow_behavior = workflow_behavior.to_s.presence || "skip"
    @batch_size        = batch_size.to_i

    @deleted                  = 0
    @skipped                  = 0
    @failed                   = 0
    @skipped_items            = []
    @errors                   = []
    @storage_reclaimed_bytes  = 0

    # Lazy-load storage backend once per run
    @storage_backend = nil
    @storage_adapter = nil
    @storage_loaded  = false
  end

  # Executes the purge and returns a {Result}.
  #
  # @return [Result]
  def call
    purge_expired_assets
    purge_expired_folders
    build_result
  end

  private

  # ---------------------------------------------------------------------------
  # Asset purge
  # ---------------------------------------------------------------------------

  def purge_expired_assets
    cutoff = @retention_days.days.ago

    Asset.trashed
         .where("deleted_at < ?", cutoff)
         .includes(:asset_versions, :workflow_instances, :collection_assets)
         .find_each(batch_size: @batch_size) do |asset|
      purge_single_asset(asset)
    end
  end

  def purge_single_asset(asset)
    # 1. Detect active workflows
    active_workflows = asset.workflow_instances.select { |wi| ACTIVE_WORKFLOW_STATUSES.include?(wi.status.to_s) }

    if active_workflows.any?
      if @workflow_behavior == "force_terminate"
        force_terminate_workflows!(active_workflows, asset)
      else
        # Default: skip — protect asset from deletion while workflow is live
        record_skip(asset, "active_workflow",
                    "Has #{active_workflows.size} active workflow instance(s): " \
                    "#{active_workflows.map(&:id).join(", ")}")
        return
      end
    end

    ActiveRecord::Base.transaction do
      # 2. Clean up duplicate-group memberships
      cleanup_duplicate_groups!(asset)

      # 3. Remove from collections (belt + suspenders — cascades handle this
      #    too, but explicit removal avoids any FK constraint surprises)
      CollectionAsset.where(asset_id: asset.id).delete_all

      # 4. Delete physical storage files
      delete_storage_files!(asset)

      # 5. Break the assets.active_version_id → asset_versions FK before destroy.
      #    Without this, cascading the version deletion violates the FK because
      #    the asset row still points at its active version.
      asset.update_column(:active_version_id, nil) if asset.active_version_id # rubocop:disable Rails/SkipsModelValidations

      # 6. Hard destroy (cascades to versions, embedding, workflow instances,
      #    tasks, and collection_assets via dependent: :destroy on Asset)
      asset.destroy!
    end

    @deleted += 1
    Rails.logger.info("[BinPurge] Permanently deleted asset ##{asset.id} '#{asset.title}'")
  rescue StandardError => e
    @failed += 1
    @errors << { id: asset.id, type: "asset", title: asset.title, message: e.message }
    Rails.logger.error("[BinPurge] Failed to purge asset ##{asset.id} '#{asset.title}': #{e.message}")
  end

  # ---------------------------------------------------------------------------
  # Folder purge
  # ---------------------------------------------------------------------------

  def purge_expired_folders
    cutoff = @retention_days.days.ago

    # Process deepest-nested folders first to avoid orphaned children.
    # We approximate depth by ordering on parent_id NULLS LAST (root last).
    Folder.trashed
          .where("deleted_at < ?", cutoff)
          .order(Arel.sql("parent_id NULLS LAST"))
          .find_each(batch_size: @batch_size) do |folder|
      purge_single_folder(folder)
    end
  end

  def purge_single_folder(folder)
    # Safety check: don't delete a folder that still contains active assets
    # (this shouldn't normally happen but guards against data anomalies).
    active_child_count = Asset.active.where(folder_id: folder.id).count +
                         Folder.active.where(parent_id: folder.id).count

    if active_child_count > 0
      record_skip(folder, "has_active_children",
                  "Contains #{active_child_count} active item(s); skipping to avoid orphaning")
      return
    end

    folder.destroy!
    @deleted += 1
    Rails.logger.info("[BinPurge] Permanently deleted folder ##{folder.id} '#{folder.name}'")
  rescue StandardError => e
    @failed += 1
    @errors << { id: folder.id, type: "folder", title: folder.name, message: e.message }
    Rails.logger.error("[BinPurge] Failed to purge folder ##{folder.id} '#{folder.name}': #{e.message}")
  end

  # ---------------------------------------------------------------------------
  # Workflow termination
  # ---------------------------------------------------------------------------

  def force_terminate_workflows!(workflow_instances, asset)
    workflow_instances.each do |wi|
      termination_entry = {
        action:     "terminated",
        reason:     "asset_purged_from_bin",
        asset_id:   asset.id,
        asset_title: asset.title,
        timestamp:  Time.current.iso8601,
      }
      wi.update!(
        status:    "terminated",
        audit_log: (wi.audit_log || []) + [ termination_entry ],
      )

      # Cancel all pending tasks so assignees are not left with dangling tasks
      wi.workflow_tasks.where(status: "pending").update_all(  # rubocop:disable Rails/SkipsModelValidations
        status: "canceled",
        comment: "Automatically cancelled — asset deleted from Recycle Bin"
      )
    end
    Rails.logger.warn("[BinPurge] Force-terminated #{workflow_instances.size} workflow(s) for asset ##{asset.id}")
  end

  # ---------------------------------------------------------------------------
  # Duplicate-group cleanup
  # ---------------------------------------------------------------------------

  def cleanup_duplicate_groups!(asset)
    DuplicateGroupAsset.cleanup_for_asset!(asset, log_prefix: "[BinPurge]")
  end

  # ---------------------------------------------------------------------------
  # Physical storage deletion — enhanced with per-version tracking
  # ---------------------------------------------------------------------------

  def delete_storage_files!(asset)
    storage = storage_adapter

    versions_purged  = 0
    versions_failed  = 0
    bytes_reclaimed  = 0

    asset.asset_versions.each do |version|
      # Calculate size BEFORE deletion for accounting
      version_size = (version.properties["size"] || 0).to_i
      storage_path = version.properties["storage_path"]

      # 1. Delete from StorageManager (S3/GCS/Azure/local)
      if storage && storage_path.present?
        storage.delete(storage_path)
        bytes_reclaimed += version_size
        versions_purged += 1
        Rails.logger.debug(
          "[BinPurge] Deleted storage v#{version.version_number} " \
          "(#{storage_path}, #{version_size} bytes) for asset ##{asset.id}"
        )
      end

      # 2. ActiveStorage blob cleanup (legacy upload path)
      version.file.purge if version.respond_to?(:file) && version.file.attached?
    rescue StandardError => e
      # Per-version failure is non-fatal — log and continue with remaining versions
      versions_failed += 1
      Rails.logger.warn(
        "[BinPurge] Storage delete failed for version ##{version.id} " \
        "(asset ##{asset.id}): #{e.message}"
      )
    end

    # 3. Legacy ActiveStorage file directly on the Asset row
    if asset.respond_to?(:file) && asset.file.attached?
      asset_size = asset.file.blob&.byte_size.to_i
      asset.file.purge
      bytes_reclaimed += asset_size
    end

    @storage_reclaimed_bytes += bytes_reclaimed

    Rails.logger.info(
      "[BinPurge] Asset ##{asset.id}: " \
      "#{versions_purged} version file(s) purged, " \
      "#{versions_failed} failed, " \
      "#{bytes_reclaimed} bytes reclaimed."
    )
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def record_skip(record, reason, detail = nil)
    type  = record.class.name.downcase
    title = record.respond_to?(:title) ? record.title : record.name
    @skipped += 1
    @skipped_items << { id: record.id, type: type, title: title, reason: reason, detail: detail }
    Rails.logger.warn("[BinPurge] Skipped #{type} ##{record.id} '#{title}' — #{reason}: #{detail}")
  end

  def build_result
    Result.new(
      deleted:                 @deleted,
      skipped:                 @skipped,
      failed:                  @failed,
      skipped_items:           @skipped_items,
      errors:                  @errors,
      storage_reclaimed_bytes: @storage_reclaimed_bytes,
    )
  end

  # Returns the storage adapter, loading it once per service run.
  def storage_adapter
    return @storage_adapter if @storage_loaded

    @storage_loaded  = true
    @storage_backend = StorageBackend.find_by(active: true)
    @storage_adapter = @storage_backend ? StorageManager.adapter_for(@storage_backend) : nil
    @storage_adapter
  end
end
