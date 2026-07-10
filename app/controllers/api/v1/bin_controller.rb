# REST API controller for the Recycle Bin.
#
# == Endpoint summary
#
# | Method | Path | Action | Description |
# |--------|------|--------|-------------|
# | GET    | /api/v1/bin | {#index} | List soft-deleted assets & folders (filterable, paginated) |
# | GET    | /api/v1/bin/stats | {#stats} | Aggregate statistics for bin contents |
# | POST   | /api/v1/bin/bulk_restore | {#bulk_restore} | Restore multiple items at once |
# | DELETE | /api/v1/bin/bulk_destroy | {#bulk_destroy} | Permanently delete multiple items |
# | DELETE | /api/v1/bin/empty | {#empty} | Permanently delete **all** trashed items |
# | GET    | /api/v1/bin/retention_policy | {#retention_policy} | Read current purge policy |
# | PUT    | /api/v1/bin/retention_policy | {#update_retention_policy} | Update purge policy (admin) |
# | POST   | /api/v1/bin/trigger_purge | {#trigger_purge} | Enqueue BinPurgeWorker (admin) |
# | GET    | /api/v1/bin/purge_status | {#purge_status} | Last run results + current status |
#
# == Retention policy
#
# Configurable via PUT /api/v1/bin/retention_policy (admin only).
# Automatic nightly purging is handled by {BinPurgeWorker} at 03:00 UTC.
#
module Api
  module V1
    class BinController < ApplicationController
      include AssetUrlHelper

      # Only skip CSRF when the caller authenticates with a bearer token (see
      # ApplicationController#token_authenticated_request?); cookie-session
      # requests still require a valid CSRF token.
      protect_from_forgery with: :null_session, if: -> { token_authenticated_request? }
      before_action :authenticate_hybrid!
      before_action :require_write_scope!, only: %i[bulk_restore bulk_destroy empty]
      before_action :require_admin!,       only: %i[update_retention_policy trigger_purge]
      before_action :require_admin_scope!, only: %i[update_retention_policy trigger_purge]

      DEFAULT_RETENTION_DAYS = 30
      VALID_SORT_FIELDS      = %w[deleted_at name size].freeze
      VALID_DIRECTIONS       = %w[asc desc].freeze

      # Lists all soft-deleted assets and folders.
      #
      # Supports the following query parameters:
      # * +q+         — case-insensitive name/title search
      # * +type+      — +asset+, +folder+, +image+, +video+, +document+, +other+, or +all+ (default)
      # * +sort+      — +deleted_at+ (default), +name+, +size+
      # * +direction+ — +desc+ (default), +asc+
      # * +page+      — 1-based page number (default 1)
      # * +per_page+  — items per page (default 25, max 100)
      #
      # @return [void] renders +200 OK+ with +{ items, pagination, retention_days }+
      def index
        q         = params[:q].to_s.strip
        type      = params[:type].to_s.presence || "all"
        sort      = VALID_SORT_FIELDS.include?(params[:sort].to_s) ? params[:sort].to_s : "deleted_at"
        direction = VALID_DIRECTIONS.include?(params[:direction].to_s) ? params[:direction].to_s : "desc"
        page      = [ params[:page].to_i, 1 ].max
        per_page  = (params[:per_page].presence || 25).to_i.clamp(1, 100)

        items = collect_bin_items(q: q, type: type, sort: sort, direction: direction)

        total = items.size
        paginated = items.slice((page - 1) * per_page, per_page) || []

        render json: {
          items:          paginated,
          pagination:     { total: total, page: page, per_page: per_page, pages: (total.to_f / per_page).ceil },
          retention_days: DEFAULT_RETENTION_DAYS,
        }
      end

      # Aggregate statistics for the bin.
      #
      # @return [void] renders +200 OK+ with statistics hash
      def stats
        trashed_assets  = Asset.trashed.includes(:active_version)
        trashed_folders = Folder.trashed

        total_size = trashed_assets.sum do |a|
          (a.active_version&.properties&.dig("size") || a.properties&.dig("size") || 0).to_i
        end

        oldest_asset  = trashed_assets.minimum(:deleted_at)
        oldest_folder = trashed_folders.minimum(:deleted_at)
        oldest_at     = [ oldest_asset, oldest_folder ].compact.min

        render json: {
          total_items:   trashed_assets.count + trashed_folders.count,
          total_assets:  trashed_assets.count,
          total_folders: trashed_folders.count,
          total_size_bytes: total_size,
          oldest_deleted_at: oldest_at,
          retention_days: DEFAULT_RETENTION_DAYS,
        }
      end

      # Bulk-restores a list of assets and/or folders.
      #
      # Expected body: +{ items: [{ id: Integer, type: "asset"|"folder" }] }+
      #
      # @return [void] renders +200 OK+ with +{ restored, errors }+
      def bulk_restore
        items   = Array(params[:items])
        restored = 0
        errors   = []

        items.each do |item|
          id   = item[:id]
          type = item[:type].to_s

          begin
            if type == "folder"
              Folder.trashed.find(id).restore
            else
              Asset.trashed.find(id).restore
            end
            restored += 1
          rescue ActiveRecord::RecordNotFound
            errors << "#{type.capitalize} ##{id} not found in bin."
          end
        end

        if restored > 0
          # Bulk restore can touch many folders at once (and reparent items
          # across the tree) — a full flush is simpler and safer than
          # tracking every affected folder id individually for a rare,
          # already-slow-path bulk operation.
          FolderContentsCache.flush_all
        end
        render json: { restored: restored, errors: errors }, status: :ok
      end

      # Permanently deletes a list of assets and/or folders.
      #
      # Expected body: +{ items: [{ id: Integer, type: "asset"|"folder" }] }+
      #
      # @return [void] renders +200 OK+ with +{ deleted, errors }+
      def bulk_destroy
        items   = Array(params[:items])
        deleted = 0
        errors  = []

        asset_ids = items.select { |i| i[:type].to_s != "folder" }.map { |i| i[:id] }
        assets_by_id = Asset.trashed.includes(:asset_versions).where(id: asset_ids).index_by { |a| a.id.to_s }

        # See the comment in {#empty} — cross-referenced active_version_id
        # pointers must be cleared for the *whole batch* up front, otherwise
        # deleting one asset can raise ActiveRecord::InvalidForeignKey because
        # another asset in the same batch still points at its version.
        version_ids = assets_by_id.values.flat_map { |a| a.asset_versions.map(&:id) }
        if version_ids.any?
          Asset.where(active_version_id: version_ids).update_all(active_version_id: nil) # rubocop:disable Rails/SkipsModelValidations
        end

        items.each do |item|
          id   = item[:id]
          type = item[:type].to_s

          begin
            if type == "folder"
              folder = Folder.trashed.find(id)
              # See the comment in {#empty} — reparent any live (non-trashed)
              # assets out of the folder first so the has_many dependent:
              # :destroy cascade never permanently deletes an asset that was
              # never actually in the bin.
              folder.assets.active.update_all(folder_id: nil) # rubocop:disable Rails/SkipsModelValidations
              folder.destroy
            else
              asset = assets_by_id[id.to_s] || raise(ActiveRecord::RecordNotFound)
              permanent_delete_asset(asset)
            end
            deleted += 1
          rescue ActiveRecord::RecordNotFound
            errors << "#{type.capitalize} ##{id} not found in bin."
          rescue StandardError => e
            errors << "Failed to delete #{type} ##{id}: #{e.message}"
          end
        end

        FolderContentsCache.flush_all if deleted > 0
        render json: { deleted: deleted, errors: errors }, status: :ok
      end

      # Permanently destroys every item currently in the bin.
      #
      # @return [void] renders +200 OK+ with +{ deleted, errors }+
      def empty
        deleted = 0
        errors  = []

        backend = ::StorageBackend.find_by(active: true)
        storage = ::StorageManager.adapter_for(backend) if backend

        trashed_assets = Asset.trashed.includes(:asset_versions).to_a
        version_ids = trashed_assets.flat_map { |a| a.asset_versions.map(&:id) }

        # Break every active_version_id FK that points at a version we're
        # about to delete — not just each asset's own pointer. Two assets can
        # end up cross-referencing the same version row (e.g. via a
        # "copy"/"save as" image-edit flow), and Postgres refuses to
        # cascade-delete an asset_versions row that's still referenced by
        # *any* row in assets.active_version_id, even one outside the current
        # batch. Nulling all of them up front avoids a mid-batch
        # ActiveRecord::InvalidForeignKey crash that would otherwise abort
        # the whole "Empty Bin" request after only partially completing.
        if version_ids.any?
          Asset.where(active_version_id: version_ids).update_all(active_version_id: nil) # rubocop:disable Rails/SkipsModelValidations
        end

        trashed_assets.each do |asset|
          asset.asset_versions.each do |version|
            storage_path = version.properties["storage_path"]
            storage&.delete(storage_path) if storage_path
            version.file.purge if version.respond_to?(:file) && version.file.attached?
          end
          detach_from_duplicate_groups(asset)
          asset.destroy
          deleted += 1
        rescue StandardError => e
          errors << "Failed to delete asset ##{asset.id}: #{e.message}"
        end

        # Trashing a folder only stamps deleted_at on the folder itself — it
        # does NOT cascade to its contents (see SoftDeletable). That means a
        # trashed folder can still legitimately contain live, non-trashed
        # assets. `Folder has_many :assets, dependent: :destroy`, so calling
        # `folder.destroy` would otherwise permanently wipe out those live
        # assets too (and could crash with ActiveRecord::InvalidForeignKey if
        # one of them still has active_version_id set). Reparent any
        # surviving live assets to the root before hard-deleting the folder
        # so we only ever destroy what was actually in the bin, and process
        # folders last since their own trashed assets were already destroyed
        # above (leaving nothing else for the cascade to touch).
        Folder.trashed.find_each do |folder|
          folder.assets.active.update_all(folder_id: nil) # rubocop:disable Rails/SkipsModelValidations
          folder.destroy
          deleted += 1
        rescue StandardError => e
          errors << "Failed to delete folder ##{folder.id}: #{e.message}"
        end

        FolderContentsCache.flush_all if deleted > 0
        render json: { deleted: deleted, errors: errors, message: "Recycle bin emptied." }, status: :ok
      end

      # Returns the current automatic purge retention policy.
      #
      # @return [void] renders +200 OK+ with the policy hash
      def retention_policy
        render json: current_policy
      end

      # Updates the automatic purge retention policy (admin only).
      #
      # Accepted parameters:
      # * +retention_days+       — Integer (1–365)
      # * +workflow_behavior+    — +"skip"+ or +"force_terminate"+
      # * +batch_size+           — Integer (1–500)
      # * +notify_admins+        — Boolean
      #
      # @return [void] renders +200 OK+ with the updated policy
      def update_retention_policy
        unless current_user&.admin?
          return render json: { error: "Administrator privileges required." }, status: :forbidden
        end

        days  = params[:retention_days].to_i
        wf    = params[:workflow_behavior].to_s.presence
        batch = params[:batch_size].to_i
        notif = params[:notify_admins]

        Setting.set("bin_retention_days", days.clamp(1, 365))      if days.positive?
        Setting.set("bin_workflow_behavior", wf)                    if %w[skip force_terminate].include?(wf)
        Setting.set("bin_purge_batch_size", batch.clamp(1, 500))   if batch.positive?
        Setting.set("bin_purge_notify_admins", notif.to_s == "true") unless notif.nil?

        render json: current_policy.merge(message: "Retention policy updated.")
      end

      # Manually enqueues {BinPurgeWorker} (admin only).
      #
      # Records who triggered the purge in Settings for audit display.
      # Returns +409+ if a purge is already running.
      #
      # @return [void] renders +200 OK+ with +{ queued: true }+
      def trigger_purge
        unless current_user&.admin?
          return render json: { error: "Administrator privileges required." }, status: :forbidden
        end

        current_status = Setting.get(BinPurgeWorker::LOCK_KEY).to_s
        if %w[running queued].include?(current_status)
          return render json: {
            error:  "A purge is already #{current_status}. Please wait for it to finish.",
            status: current_status,
          }, status: :conflict
        end

        # Stamp who triggered it before enqueueing
        Setting.set(BinPurgeWorker::LOCK_KEY, "queued")
        Setting.set("bin_purge_triggered_by", {
          user_id:   current_user.id,
          user_name: current_user.name,
          user_email: current_user.email,
          triggered_at: Time.current.iso8601,
          source: "manual",
        })
        Setting.set("bin_purge_started_at", Time.current.iso8601)

        BinPurgeWorker.perform_async

        render json: {
          queued:       true,
          message:      "Bin purge has been queued.",
          triggered_by: current_user.name,
        }
      end

      # Returns the current purge status and the results of the last completed run.
      #
      # @return [void] renders +200 OK+ with +{ status, last_ran_at, triggered_by, last_results, policy }+
      def purge_status
        raw_results    = Setting.get("bin_purge_last_results")
        triggered_by   = Setting.get("bin_purge_triggered_by")

        render json: {
          status:        Setting.get(BinPurgeWorker::LOCK_KEY).to_s.presence || "idle",
          last_ran_at:   Setting.get("bin_purge_last_ran_at"),
          started_at:    Setting.get("bin_purge_started_at"),
          triggered_by:  triggered_by.is_a?(Hash) ? triggered_by : {},
          last_results:  raw_results.is_a?(Hash) ? raw_results : {},
          policy:        current_policy,
        }
      end

      # ── AI-powered smart suggestions (stub — routed to AI gateway) ─────────────
      #
      # Returns an opinionated list of items that the AI gateway recommends
      # permanently purging based on: staleness, low access count, duplicate
      # checksums, and absence of collection memberships.
      #
      # The actual ML inference runs in the Capri AI Gateway
      # (https://github.com/Capri-Labs/capri-dam-ai-gateway).
      # Until the gateway is wired up this endpoint returns the top-N expired
      # items ranked by a simple heuristic so the UI surface is ready.
      #
      # @return [void] renders +200 OK+ with +{ suggestions, ai_available, model }+
      def ai_smart_suggestions
        unless current_user&.admin?
          return render json: { error: "Administrator privileges required." }, status: :forbidden
        end

        limit      = (params[:limit].presence || 20).to_i.clamp(1, 50)
        threshold  = (Setting.get("bin_retention_days") || BinPurgeWorker::DEFAULT_RETENTION_DAYS).to_i.days.ago

        # Heuristic scoring until AI gateway is live:
        # score = age_factor * (1 - has_collection_pin) * (1 - has_active_workflow)
        candidate_assets = Asset.trashed
                                .where("deleted_at < ?", threshold)
                                .includes(:collection_assets, :workflow_instances, :active_version)
                                .order("deleted_at ASC")
                                .limit(limit * 3) # over-fetch to allow scoring filter

        suggestions = candidate_assets.map do |a|
          age_days    = ((Time.current - a.deleted_at) / 86_400).to_i
          has_coll    = a.collection_assets.any?
          has_wf      = a.workflow_instances.any? { |wi| BinPurgeService::ACTIVE_WORKFLOW_STATUSES.include?(wi.status.to_s) }
          props       = a.active_version&.properties || a.properties
          size_bytes  = (props["size"] || 0).to_i

          {
            id:           a.id,
            title:        a.title,
            deleted_at:   a.deleted_at,
            age_days:     age_days,
            size_bytes:   size_bytes,
            size_human:   format_size(size_bytes),
            has_collection_pin: has_coll,
            has_active_workflow: has_wf,
            # AI-readiness fields (populated by gateway once live)
            ai_risk_score: nil,   # 0–100; higher = safer to delete
            ai_reason:     nil,   # human-readable explanation from LLM
            ai_tags:       [],    # semantic tags inferred from content
            # Simple heuristic score while AI gateway is pending
            heuristic_score: compute_heuristic(age_days, size_bytes, has_coll, has_wf),
          }
        end

        suggestions = suggestions
                        .reject { |s| s[:has_active_workflow] }
                        .sort_by { |s| -s[:heuristic_score] }
                        .first(limit)

        render json: {
          suggestions:   suggestions,
          ai_available:  false, # set to true once AI gateway /bin/smart-cleanup is wired
          model:         nil,   # e.g. "capri-cleanup-v1"
          gateway_url:   "https://github.com/Capri-Labs/capri-dam-ai-gateway",
          heuristic_note: "Scores are rule-based until the AI gateway is integrated.",
        }
      end

      # ── AI cleanup report (stub) ────────────────────────────────────────────────
      #
      # Returns a human-readable cleanup report that will eventually be generated
      # by the AI gateway (summarising what was deleted, storage recovered, and any
      # anomalies detected).  Currently returns a structured placeholder.
      #
      # @return [void] renders +200 OK+ with the report stub
      def ai_cleanup_report
        unless current_user&.admin?
          return render json: { error: "Administrator privileges required." }, status: :forbidden
        end

        last_results = Setting.get("bin_purge_last_results") || {}

        render json: {
          generated_at:   Time.current.iso8601,
          ai_available:   false,
          report: {
            summary:         "AI-generated summary is not yet available. The AI gateway integration is pending.",
            items_deleted:   last_results["deleted"] || last_results[:deleted] || 0,
            items_skipped:   last_results["skipped"] || last_results[:skipped] || 0,
            storage_reclaimed_bytes: last_results["storage_reclaimed_bytes"] || 0,
            anomalies:       [],  # AI will populate: unusual deletion patterns, potential data loss risks
            recommendations: [],  # AI will populate: policy tuning suggestions
            next_actions:    [
              "Connect the Capri AI Gateway to enable intelligent cleanup reports.",
              "See: https://github.com/Capri-Labs/capri-dam-ai-gateway",
            ],
          },
        }
      end

      private

      # Collects and serialises all trashed items applying search/type/sort.
      def collect_bin_items(q:, type:, sort:, direction:)
        include_assets  = !%w[folder].include?(type)
        include_folders = !%w[asset image video document other].include?(type)

        items = []

        if include_folders
          folders = Folder.trashed
          folders = folders.where("name ILIKE ?", "%#{q}%") if q.present?
          items += folders.map { |f| serialize_folder(f) }
        end

        if include_assets
          assets = Asset.trashed.includes(:active_version)
          assets = assets.where("title ILIKE ? OR properties->>'original_filename' ILIKE ?", "%#{q}%", "%#{q}%") if q.present?
          assets = filter_by_media_type(assets, type)
          items += assets.map { |a| serialize_asset(a) }
        end

        sort_items(items, sort: sort, direction: direction)
      end

      DOCUMENT_CONTENT_TYPES = %w[
        application/pdf application/msword
        application/vnd.openxmlformats-officedocument.wordprocessingml.document
        application/vnd.ms-excel
        application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      ].freeze

      def filter_by_media_type(scope, type)
        case type
        when "image"    then scope.where("properties->>'content_type' LIKE ?", "image/%")
        when "video"    then scope.where("properties->>'content_type' LIKE ?", "video/%")
        when "document" then scope.where("properties->>'content_type' IN (?)", DOCUMENT_CONTENT_TYPES)
        when "other"
          # Anything that isn't an image, a video, or a recognised document
          # type falls into the catch-all "Other" bucket (e.g. audio, zip
          # archives, raw/uncommon formats, or assets with no content type).
          scope.where.not(
            "COALESCE(properties->>'content_type', '') LIKE ? OR COALESCE(properties->>'content_type', '') LIKE ?",
            "image/%", "video/%",
          ).where.not("COALESCE(properties->>'content_type', '') IN (?)", DOCUMENT_CONTENT_TYPES)
        else scope
        end
      end

      def sort_items(items, sort:, direction:)
        sorted = case sort
        when "name"
                   items.sort_by { |i| (i[:name] || "").downcase }
        when "size"
                   items.sort_by { |i| i[:size_bytes].to_i }
        else # deleted_at
                   items.sort_by { |i| i[:deleted_at] || Time.at(0) }
        end

        direction == "asc" ? sorted : sorted.reverse
      end

      def serialize_asset(asset)
        props        = asset.properties.merge(asset.active_version&.properties || {})
        content_type = props["content_type"].to_s
        size_bytes   = (props["size"] || 0).to_i
        expires_at   = asset.deleted_at + DEFAULT_RETENTION_DAYS.days if asset.deleted_at

        {
          id:           asset.uuid,
          uuid:         asset.uuid,
          grid_id:      "asset_#{asset.id}",
          item_type:    "asset",
          media_type:   derive_media_type(content_type),
          name:         asset.title || props["original_filename"] || "Unknown",
          status:       asset.status,
          deleted_at:   asset.deleted_at,
          expires_at:   expires_at,
          expired:      expires_at.present? && expires_at < Time.current,
          size_bytes:   size_bytes,
          size_human:   props["size_human"] || format_size(size_bytes),
          content_type: content_type,
          original_path: asset.folder&.name,
          url:          asset_url_for(asset),
          # Prefer the web-renderable preview (e.g. a flattened PNG generated
          # for PSD/TIFF/HEIC) so non-browser-native formats still show a
          # thumbnail in the bin grid, mirroring Folders/Assets/Search.
          preview_url:  asset_preview_url_for(asset),
          properties:   props,
          editable:     AssetProcessorWorker::WEB_RENDERABLE_MIME_TYPES.include?(content_type),
        }
      end

      def serialize_folder(folder)
        expires_at = folder.deleted_at + DEFAULT_RETENTION_DAYS.days if folder.deleted_at

        {
          id:           folder.id,
          grid_id:      "folder_#{folder.id}",
          item_type:    "folder",
          media_type:   "folder",
          name:         folder.name,
          deleted_at:   folder.deleted_at,
          expires_at:   expires_at,
          expired:      expires_at.present? && expires_at < Time.current,
          size_bytes:   0,
          size_human:   nil,
          content_type: nil,
          original_path: nil,
          url:          nil,
          preview_url:  nil,
          properties:   {},
        }
      end

      def derive_media_type(content_type)
        return "image"    if content_type.start_with?("image/")
        return "video"    if content_type.start_with?("video/")
        return "audio"    if content_type.start_with?("audio/")
        return "model_3d" if ThreeDMimeTypes.model_3d?(content_type)
        return "document" if content_type.include?("pdf") || content_type.include?("word") ||
                              content_type.include?("excel") || content_type.include?("spreadsheet") ||
                              content_type.include?("presentation")
        "file"
      end

      def format_size(bytes)
        return "0 B" if bytes == 0
        units = %w[B KB MB GB TB]
        exp   = (Math.log(bytes) / Math.log(1024)).floor
        exp   = [ exp, units.length - 1 ].min
        "%.1f %s" % [ bytes.to_f / 1024**exp, units[exp] ]
      end

      def permanent_delete_asset(asset)
        backend = ::StorageBackend.find_by(active: true)
        storage = ::StorageManager.adapter_for(backend) if backend

        asset.asset_versions.each do |version|
          storage_path = version.properties["storage_path"]
          if storage && storage_path.present?
            storage.delete(storage_path)
          end
          # ActiveStorage legacy blob
          version.file.purge if version.respond_to?(:file) && version.file.attached?
        rescue StandardError => e
          Rails.logger.warn("[BinController] Storage delete failed for version ##{version.id}: #{e.message}")
        end

        # Legacy asset-level blob
        asset.file.purge if asset.respond_to?(:file) && asset.file.attached?

        # Break the active_version_id FK before cascading version deletion
        asset.update_column(:active_version_id, nil) if asset.active_version_id # rubocop:disable Rails/SkipsModelValidations
        detach_from_duplicate_groups(asset)
        asset.destroy
      end

      # Removes any {DuplicateGroupAsset} join rows referencing +asset+ before
      # it is hard-deleted. `DuplicateGroupAsset belongs_to :asset` with an FK
      # constraint (fk_rails_e5995b56ce) but neither {Asset} nor
      # {DuplicateGroupAsset} declares a `dependent:` option on that side, so
      # Postgres raises ActiveRecord::InvalidForeignKey if an asset that's
      # still a duplicate-group member (e.g. Duplicate Manager demo/seed data,
      # or any asset a user never resolved/dismissed in that feature) is
      # permanently deleted from the bin. Detach it here and recompute each
      # affected group's cached +total_count+; a group left with zero members
      # is no longer meaningful, so it's destroyed too (dependent: :destroy
      # already cleans up its own duplicate_group_assets).
      #
      # @param asset [Asset]
      # @return [void]
      def detach_from_duplicate_groups(asset)
        memberships = DuplicateGroupAsset.where(asset_id: asset.id).to_a
        return if memberships.empty?

        group_ids = memberships.map(&:duplicate_group_id).uniq
        DuplicateGroupAsset.where(asset_id: asset.id).delete_all

        DuplicateGroup.where(id: group_ids).find_each do |group|
          remaining = group.duplicate_group_assets.count
          if remaining.zero?
            group.destroy
          else
            group.update_column(:total_count, remaining) # rubocop:disable Rails/SkipsModelValidations
          end
        end
      end

      # ---------------------------------------------------------------------------
      # Retention policy helper
      # ---------------------------------------------------------------------------

      def current_policy
        {
          retention_days:    (Setting.get("bin_retention_days")         || BinPurgeWorker::DEFAULT_RETENTION_DAYS).to_i,
          workflow_behavior: (Setting.get("bin_workflow_behavior")       || BinPurgeWorker::DEFAULT_WORKFLOW_BEHAVIOR).to_s,
          batch_size:        (Setting.get("bin_purge_batch_size")        || BinPurgeWorker::DEFAULT_BATCH_SIZE).to_i,
          notify_admins:     Setting.get("bin_purge_notify_admins").nil? ? BinPurgeWorker::DEFAULT_NOTIFY_ADMINS : (Setting.get("bin_purge_notify_admins").to_s == "true"),
          next_scheduled_at: next_scheduled_purge,
        }
      end

      def next_scheduled_purge
        # Approximate "next 03:00 UTC" for display purposes
        candidate = Time.current.utc.change(hour: 3, min: 0, sec: 0)
        candidate += 1.day if candidate <= Time.current.utc
        candidate.iso8601
      end

      # ---------------------------------------------------------------------------
      # AI heuristic helpers
      # ---------------------------------------------------------------------------

      # Simple heuristic score (0–100) used until the AI gateway is live.
      # Factors: age (older = higher score), size (larger = higher score as more
      # storage reclaimed), absence of collection pin, absence of active workflow.
      def compute_heuristic(age_days, size_bytes, has_collection_pin, has_active_workflow)
        return 0 if has_active_workflow

        age_score  = [ age_days.to_f / 365 * 40, 40 ].min         # max 40 pts
        size_score = [ Math.log10([ size_bytes, 1 ].max) * 4, 30 ].min  # max 30 pts
        pin_score  = has_collection_pin ? 0 : 20                   # 20 pts if not pinned
        base_score = 10                                             # base 10 pts

        (age_score + size_score + pin_score + base_score).round
      end
    end
  end
end
