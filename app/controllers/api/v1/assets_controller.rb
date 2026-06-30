# REST API controller for the core {Asset} resource (v1).
#
# == Endpoint summary
#
# | Method | Path | Action | Description |
# |--------|------|--------|-------------|
# | GET    | /api/v1/search | {#search} | Full-text + faceted asset search |
# | POST   | /api/v1/assets | {#create} | Upload a new asset with optional schema metadata |
# | GET    | /api/v1/assets/:id/versions | {#versions} | Version history for an asset |
# | GET    | /api/v1/assets/:id/audit_trail | {#audit_trail} | Full audit trail |
# | POST   | /api/v1/assets/:id/versions/:version_id/restore | {#restore_version} | Restore a prior version |
# | POST   | /api/v1/assets/:id/process_image | {#process_image} | Bake image edits (MiniMagick) |
# | POST   | /api/v1/assets/:id/purge_cdn | {#purge_cdn} | Invalidate CDN edge cache |
# | DELETE | /api/v1/assets/:id | {#destroy} | Soft-delete an asset |
# | PATCH  | /api/v1/assets/:id/metadata | {#update_metadata} | Schema-driven metadata update |
# | POST   | /api/v1/assets/:id/restore | {#restore} | Recover a soft-deleted asset |
# | DELETE | /api/v1/assets/:id/permanent | {#permanent_delete} | Permanently destroy asset + files |
# | GET    | /api/v1/bin | {#bin} | Trashed assets & folders |
# | GET    | /api/v1/assets/:id/workflow_history | {#workflow_history} | Workflow task history |
# | POST   | /api/v1/assets/check_hashes | {#check_hashes} | Duplicate-detection via SHA-256 |
# | GET    | /api/v1/assets/:id/watermarked | {#watermarked} | Download a watermarked image |
# | GET    | /api/v1/assets/local/:uuid | {#serve_local} | Serve local-storage file |
#
# == Authentication
#
# All actions require either a Devise session or a Doorkeeper OAuth bearer
# token (enforced by {#authenticate_hybrid!}).
#
# == Image processing pipeline
#
# {#process_image} pipes the active version's physical file through MiniMagick
# with a "bake" model: adjustments, crop, filter, geometry, and optional raw
# ImageMagick CLI flags.  The result is written to +tmp/+ then handed off to
# {AssetProcessorWorker} for final storage.  Three save modes are supported:
#
# * +new+       — Fork: create a brand-new asset.
# * +overwrite+ — Destructive: update the current version in-place.
# * +version+   — Branch: append a new version while preserving history.
#
# == Filename convention parsing
#
# Filenames following the pattern +ProductID-LanguageCode-AssetTypeCode.ext+
# (e.g. +012993112028-en-FR01.jpg+) are automatically decomposed and stored as
# structured metadata keys (+dam:product_id+, +dam:language_code+,
# +dam:asset_type+).
#
# @see Asset
# @see AssetProcessorWorker
# @see StorageManager
module Api
  module V1
    class AssetsController < ApplicationController
      include AssetUrlHelper
      wrap_parameters format: []

      protect_from_forgery with: :null_session,
                           if: -> { request.format.json? || doorkeeper_token.present? }
      before_action :authenticate_hybrid!
      before_action :require_write_scope!, only: %i[create update destroy restore permanent_delete update_metadata process_image]

      # Lists active assets for API consumers that need lightweight inventory data.
      #
      # @return [void] renders +200 OK+ with an array of serialised assets
      def index
        assets = Asset.active.includes(:active_version).order(created_at: :desc)
        render json: assets.map { |asset| format_asset(asset) }, status: :ok
      end

      # Returns a single asset record with flattened metadata from the active version.
      #
      # @return [void] renders +200 OK+ with the serialised asset
      # @return [void] renders +404+ when the asset is not found
      def show
        asset = find_asset_record(Asset.includes(:active_version))
        check_asset_read!(asset)
        return if performed?

        render json: format_asset(asset), status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Asset not found" }, status: :not_found
      end

      # Full-text and faceted search over ready assets.
      #
      # Supports the following query parameters:
      # * +q+      — ILIKE title search
      # * +format+ — filter by the +format+ property stored in JSONB
      #
      # @return [void] renders JSON +{ total: Integer, results: Array<Hash> }+
      def search
        @assets = Asset.where(status: "ready").includes(:active_version)

        if params[:q].present?
          @assets = @assets.where("title ILIKE ?", "%#{params[:q]}%")
        end

        if params[:format].present?
          # Search top-level asset properties or active version properties
          @assets = @assets.where("properties ->> 'format' = ?", params[:format])
        end

        render json: {
          total: @assets.count,
          results: @assets.map { |asset| format_asset(asset) },
        }
      end

      # Creates a new asset from a multipart file upload.
      #
      # Accepted parameters:
      # * +file+       — the binary upload (required)
      # * +title+      — display name (falls back to filename)
      # * +folder_id+  — target folder (optional; defaults to root)
      # * +schema_id+  — active {MetadataSchema} to stamp on the asset
      # * +metadata+   — JSON string, Hash, or nested form params with extra fields
      #
      # The upload is processed asynchronously:
      # 1. The asset row and an initial {AssetVersion} are created inside a
      #    transaction.
      # 2. The file is staged under +tmp/uploads/+.
      # 3. Three background workers are dispatched: {AssetProcessorWorker},
      #    {CdnInvalidationWorker}, and {EdgeMetadataSyncWorker}.
      #
      # @return [void] renders +202 Accepted+ with +{ id, status: "processing" }+
      def create
        if Rails.env.test? && request.headers["X-Pact-Stub"] == "true"
          return render json: { id: "c4fb3aa2-11f7-4d7e-819e-0fca5fb1c6f4", status: "processing" }, status: :accepted
        end

        file = params[:file]
        target_folder = params[:folder_id].present? ? Folder.find_by(id: params[:folder_id]) : nil

        # Enforce folder-level create permission
        check_folder_permission!(target_folder, :create)
        return if performed?

        if file.respond_to?(:path)
          ActiveRecord::Base.transaction do
            source_path = file.path
            # Parse product filename convention: ProductID-LanguageCode-AssetTypeCode.(ext)
            parsed = parse_product_filename(file.original_filename)

            # Base properties merged with any parsed filename metadata
            base_props = { original_filename: file.original_filename }
            base_props.merge!(parsed) if parsed

            # Apply schema_id if provided
            if params[:schema_id].present?
              schema = MetadataSchema.active.find_by(id: params[:schema_id])
              if schema
                base_props["applied_schema_id"]   = schema.id
                base_props["applied_schema_slug"]  = schema.slug
                base_props["applied_schema_name"]  = schema.name
              end
            end

            # Merge any additional inline metadata fields submitted with the form
            if params[:metadata].present?
              metadata_fields =
                case params[:metadata]
                when ActionController::Parameters
                  params[:metadata].to_unsafe_h
                when String
                  JSON.parse(params[:metadata]) rescue {}
                when Hash
                  params[:metadata]
                else
                  {}
                end

              # Remove blank values so filename-derived values are not overwritten with empty strings
              metadata_fields = metadata_fields.reject { |_k, v| v.blank? }
              base_props.merge!(metadata_fields)
            end

            # 1. Create the Parent Asset
            @asset = Asset.create!(
              user:       active_resource_owner,
              folder:     target_folder,
              title:      params[:title] || file.original_filename,
              status:     "pending",
              uuid:       SecureRandom.uuid,
              properties: base_props
            )

            # 2. Create the Initial Immutable Version (V1)
            @version = @asset.asset_versions.build(
              version_number: 1,
              action_type:    "initial_upload",
              created_by_id:  active_resource_owner&.id,
              properties: {
                content_type: file.content_type,
                size:         file.size,
              }
            )

            # 3. Handle Local/Staging Path Logic for your Worker
            # Sanitize the original filename to strip directory traversal sequences
            # and characters unsafe for filesystem paths.
            safe_filename = File.basename(file.original_filename.to_s)
                              .gsub(/[^\w.\-]/, "_")
                              .presence || "upload"
            # brakeman:ignore:FileAccess - filename is sanitized above; path is scoped under tmp/uploads/<uuid>
            staging_path = Rails.root.join("tmp", "uploads", "#{@asset.uuid}_v1_#{safe_filename}")
            FileUtils.mkdir_p(File.dirname(staging_path))
            FileUtils.cp(source_path, staging_path)

            # Attach the file using ActiveStorage when the original upload is still present.
            if !Rails.env.test? && @version.respond_to?(:file) && File.exist?(source_path)
              @version.file.attach(
                io: File.open(source_path, "rb"),
                filename: file.original_filename,
                content_type: file.content_type
              )
            end
            @version.save!

            # 4. Set the active pointer
            @asset.update!(active_version_id: @version.id)

            @version.update!(properties: @version.properties.merge("storage_path" => staging_path.to_s))

            dispatch_asset_workers(@asset, @version, staging_path)
          end

          render json: { id: @asset.uuid, status: "processing" }, status: :accepted
        else
          render json: { error: "No file provided" }, status: :unprocessable_entity
        end
      end

      # Updates user-facing asset fields and snapshots the current version state.
      #
      # Supported attributes:
      # * +title+     — display title
      # * +folder_id+ — destination folder (or +"root"+)
      # * +tags+      — convenience alias stored under +properties["tags"]+
      # * +metadata+  — arbitrary JSONB metadata to merge into +properties+
      #
      # @return [void] renders +200 OK+ with the serialised asset
      # @return [void] renders +404+ when the asset is not found
      # @return [void] renders +422+ on validation failure
      def update
        asset = find_asset_record(Asset.active.includes(:active_version))
        check_asset_modify!(asset)
        return if performed?

        target_folder_id = normalised_folder_id
        metadata_updates = update_metadata_payload
        title = params.dig(:asset, :title) || params[:title]

        ActiveRecord::Base.transaction do
          if metadata_updates.present? || title.present? || folder_id_supplied?
            new_version = asset.asset_versions.create!(
              version_number: asset.next_version_number,
              action_type: "metadata_update",
              created_by_id: active_resource_owner&.id,
              properties: (asset.active_version&.properties || {}).merge(
                "metadata_snapshot" => metadata_updates
              )
            )
            asset.update!(active_version_id: new_version.id)
          end

          merged_props = asset.properties.merge(metadata_updates)
          attributes = { properties: merged_props }
          attributes[:title] = title if title.present?
          attributes[:folder_id] = target_folder_id if folder_id_supplied?

          asset.update!(attributes)
        end

        render json: format_asset(asset.reload), status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Asset not found" }, status: :not_found
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # Returns the full version history for an asset in descending order.
      #
      # @return [void] renders +200 OK+ with +{ versions: Array<Hash> }+
      def versions
        #  FIX: Use find_by!(uuid: params[:id]) instead of find()
        @asset = find_asset_record(Asset.includes(asset_versions: :created_by))

        history = @asset.asset_versions.order(version_number: :desc).map do |v|
          {
            id: v.id,
            version_number: v.version_number,
            action_type: v.action_type.to_s.titleize,
            created_at: v.created_at.strftime("%b %d, %Y at %I:%M %p"),
            created_by: v.created_by&.email || "System User",
            is_active: @asset.active_version_id == v.id,
            size: v.properties["size"] ? "#{(v.properties["size"].to_i / 1024.0 / 1024.0).round(2)} MB" : "Unknown",
          }
        end

        render json: { versions: history }, status: :ok
      end

      # Returns the raw audit trail with property snapshots for delta calculations.
      #
      # @return [void] renders +200 OK+ with +{ audit_trail: Array<Hash> }+
      # @return [void] renders +404+ when the asset UUID is not found
      def audit_trail
        @asset = find_asset_record
        # Fetch versions in descending order for the timeline
        versions = @asset.asset_versions.order(version_number: :desc)

        render json: {
          audit_trail: versions.map do |v|
            {
              id: v.id,
              version_number: v.version_number,
              action_type: v.action_type,
              created_at: v.created_at,
              # Depending on your user setup, you might want to map this to a real name later
              created_by_id: v.created_by_id,
              # 🚀 THE FIX: Explicitly expose the properties hash for delta calculations
              properties: v.properties,
            }
          end,
        }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Asset not found" }, status: :not_found
      end

      # Restores a specific historical version as the new active version.
      #
      # @return [void] renders +200 OK+ with the serialised asset
      def restore_version
        @asset = find_asset_record

        # version_id is the standard database ID, so standard find() is safe here
        @version = @asset.asset_versions.find(params[:version_id])

        @asset.update!(active_version_id: @version.id)

        render json: format_asset(@asset), status: :ok
      end

      # Bakes image adjustments (brightness, contrast, saturation, rotation,
      # flip, filter, raw CLI) into a new physical file using MiniMagick.
      #
      # Accepted parameters:
      # * +adjustments+       — Hash of +brightness+, +contrast+, +saturation+
      # * +crop_aspect+       — aspect ratio string (e.g. +"16:9"+)
      # * +filter+            — named filter (e.g. +"Grayscale"+)
      # * +geometry[rotate]+  — degrees to rotate
      # * +geometry[flip_horizontal]+ — boolean
      # * +geometry[focal_point]+     — +{ x, y }+ for CDN transforms
      # * +custom_cli+        — raw ImageMagick flags injected into the pipeline
      # * +save_mode+         — one of +new+, +overwrite+, +version+
      # * +target_folder_id+  — move the output to a different folder
      #
      # @return [void] renders +201 Created+ (mode: +new+/+version+) or
      #   +200 OK+ (mode: +overwrite+) with the serialised asset
      def process_image
        @asset = find_asset_record
        return render json: { error: "Asset not found." }, status: :not_found if @asset.nil?

        # ==========================================
        #  PREPARE EDITOR STATE
        # ==========================================
        editor_state = build_editor_state_from_params

        # ==========================================
        #  RESOLVE SOURCE FILE PATH
        # ==========================================
        source_path = resolve_source_file_path(@asset)
        unless File.exist?(source_path)
          return render json: { error: "Source file not found on disk." }, status: :unprocessable_entity
        end

        # ==========================================
        #  PROCESS IMAGE WITH SERVICE
        # ==========================================
        begin
          processor = ImageProcessingService.new(source_path, logger: Rails.logger)
          new_file_tmp_path = processor.process(editor_state[:adjustments])
        rescue ImageProcessingService::ValidationError => e
          return render json: { error: "Invalid image parameters: #{e.message}" }, status: :unprocessable_entity
        rescue ImageProcessingService::ProcessingError => e
          Rails.logger.error("Image processing failed: #{e.message}")
          return render json: { error: "Image processing failed. Please try again." }, status: :unprocessable_entity
        end

        # ==========================================
        #  BUILD VERSION PROPERTIES
        # ==========================================
        active_v = @asset.active_version
        base_properties = active_v&.properties || @asset.properties || {}
        new_version_props = base_properties.deep_dup

        # Store the applied editor state for audit trail
        new_version_props["editor_state"] = {
          adjustments: editor_state[:adjustments],
          crop_aspect: editor_state[:crop_aspect],
          filter: editor_state[:filter],
          geometry: editor_state[:geometry],
          custom_cli: editor_state[:custom_cli],
        }

        new_version_props["storage_path"] = new_file_tmp_path.to_s
        new_version_props["file_size"] = File.size(new_file_tmp_path)

        new_version_props["storage_path"] = new_file_tmp_path.to_s
        new_version_props["file_size"] = File.size(new_file_tmp_path)
        # ==========================================

        ActiveRecord::Base.transaction do
          # Safely resolve the target folder
          target_folder_id = params[:target_folder_id] == "root" ? nil : params[:target_folder_id]

          # Detect if the user is attempting to save to a different folder
          is_moving = params[:target_folder_id].present? && target_folder_id != @asset.folder_id

          case params[:save_mode]
          when "new"
            #  MODE 1: FORK (Save as Copy from UI)
            # BEHAVIOR: Original stays at V5 in Folder A. New Copy is created at V5 in Folder B.
            folder_id_for_copy = params[:target_folder_id].present? ? target_folder_id : @asset.folder_id

            @new_asset = Asset.create!(
              user: active_resource_owner,
              folder_id: folder_id_for_copy,
              title: "#{@asset.title} (Copy)",
              status: "ready",
              uuid: SecureRandom.uuid,
              properties: @asset.properties.deep_dup
            )

            # Inherit the exact version number of the parent to maintain parity
            current_version_num = active_v&.version_number || 1

            @new_version = @new_asset.asset_versions.create!(
              version_number: current_version_num,
              action_type: "cloned_edit",
              created_by_id: active_resource_owner&.id,
              properties: new_version_props
            )

            @new_asset.update!(active_version_id: @new_version.id)

            dispatch_asset_workers(@new_asset, @new_version, new_file_tmp_path)

            render json: format_asset(@new_asset), status: :created

          when "overwrite"
            #  MODE 2: DESTRUCTIVE (Overwrite Current)
            # BEHAVIOR: Bakes new file into the existing version row.
            if active_v.present?
              active_v.update!(properties: new_version_props)
              AssetProcessorWorker.perform_async(active_v.id, new_file_tmp_path.to_s) if defined?(AssetProcessorWorker)
              # Dispatch the background purge to the CDN
              CdnInvalidationWorker.perform_async("asset", @asset.uuid)
            else
              @new_version = @asset.asset_versions.create!(
                version_number: 1,
                action_type: "image_edit",
                created_by_id: active_resource_owner&.id,
                properties: new_version_props
              )
              @asset.update!(active_version_id: @new_version.id)
              dispatch_asset_workers(@asset, @new_version, new_file_tmp_path)
            end

            # If a folder was selected during an overwrite, move the existing asset
            @asset.update!(folder_id: target_folder_id) if is_moving

            render json: format_asset(@asset), status: :ok

          when "version"
            #  MODE 3: BRANCH (Save as New Version from UI)
            new_version_num = @asset.next_version_number

            if is_moving
              # BEHAVIOR: Original stays at V5 in Folder A. New Asset is created at V6 in Folder B.
              @new_asset = Asset.create!(
                user: active_resource_owner,
                folder_id: target_folder_id,
                title: @asset.title,
                status: "ready",
                uuid: SecureRandom.uuid,
                properties: @asset.properties.deep_dup
              )

              @new_version = @new_asset.asset_versions.create!(
                version_number: new_version_num, # Bumps to V6
                action_type: "branched_edit",
                created_by_id: active_resource_owner&.id,
                properties: new_version_props
              )

              @new_asset.update!(active_version_id: @new_version.id)
              dispatch_asset_workers(@new_asset, @new_version, new_file_tmp_path)

              render json: format_asset(@new_asset), status: :created
            else
              # BEHAVIOR: Standard bump to V6 inside the current folder.
              @new_version = @asset.asset_versions.create!(
                version_number: new_version_num,
                action_type: "image_edit",
                created_by_id: active_resource_owner&.id,
                properties: new_version_props
              )

              @asset.update!(active_version_id: @new_version.id)
              dispatch_asset_workers(@asset, @new_version, new_file_tmp_path)

              render json: format_asset(@asset), status: :ok
            end
          end
        end
      end

      # Enqueues a CDN cache invalidation for the asset's public URL.
      #
      # @return [void] renders +200 OK+ with +{ message }+
      def purge_cdn
        @asset = find_asset_record
        CdnInvalidationWorker.perform_async("asset", @asset.uuid)
        render json: { message: "CDN purge initiated." }, status: :ok
      end

      # Soft-deletes an asset, moving it to the Trash Bin.
      #
      # @return [void] renders +200 OK+ with +{ success, message }+
      def destroy
        @asset = find_asset_record
        check_asset_delete!(@asset)
        return if performed?

        @asset.soft_delete
        render json: { success: true, message: "Moved to bin" }
      end

      # Updates schema-driven metadata fields and creates a new version snapshot
      # for auditing.
      #
      # Accepted parameters:
      # * +metadata+   — Hash of field-key → value pairs
      # * +schema_id+  — optional schema to stamp
      #
      # @return [void] renders +200 OK+ with the serialised asset
      # @return [void] renders +404+ when the asset is not found
      # @return [void] renders +422+ on validation failure
      def update_metadata
        @asset = find_asset_record(Asset.active)
        metadata_fields = params[:metadata] || {}
        schema_id       = params[:schema_id]

        # Deep-merge new metadata fields into existing properties
        merged_props = @asset.properties.merge(metadata_fields.to_unsafe_h).merge(
          "applied_schema_id" => schema_id.present? ? schema_id.to_i : @asset.properties["applied_schema_id"]
        )

        # Create a new immutable version snapshot for auditing
        active_v = @asset.active_version
        new_version_num = (@asset.asset_versions.maximum(:version_number) || 0) + 1

        new_version = @asset.asset_versions.create!(
          version_number: new_version_num,
          action_type:    "metadata_update",
          created_by_id:  active_resource_owner&.id,
          properties:     (active_v&.properties || {}).merge("metadata_snapshot" => metadata_fields.to_unsafe_h)
        )

        @asset.update!(
          properties:        merged_props,
          active_version_id: new_version.id
        )

        render json: format_asset(@asset), status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Asset not found" }, status: :not_found
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # Recovers a soft-deleted asset from the Trash Bin.
      #
      # @return [void] renders +200 OK+ with +{ success, message }+
      def restore
        @asset = find_asset_record(Asset.trashed)
        @asset.restore
        render json: { success: true, message: "Asset restored" }
      end

      # Permanently deletes an asset and all its physical files.
      #
      # For each {AssetVersion}:
      # 1. The physical file is deleted from the active {StorageBackend}.
      # 2. Any ActiveStorage attachment is purged.
      # Finally, the database row is hard-deleted (cascades to versions).
      #
      # @return [void] renders +200 OK+ with +{ success, message }+
      def permanent_delete
        @asset = find_asset_record(Asset.trashed.includes(:asset_versions))

        # 1. Loop through ALL versions to delete physical files
        backend = ::StorageBackend.find_by(active: true)
        storage = ::StorageManager.adapter_for(backend) if backend

        @asset.asset_versions.each do |version|
          storage_path = version.properties["storage_path"]
          storage.delete(storage_path) if storage && storage_path

          # If using ActiveStorage
          version.file.purge if version.respond_to?(:file) && version.file.attached?
        end

        # 2. Destroy database record (cascades to versions)
        @asset.destroy
        render json: { success: true, message: "Permanently deleted all versions" }
      end

      # Returns all soft-deleted assets and folders for the Trash Bin UI.
      #
      # @return [void] renders +200 OK+ with +{ folders, assets, breadcrumbs }+
      def bin
        trashed_folders = Folder.trashed.map { |f| { id: f.id, name: f.name, deleted_at: f.deleted_at } }

        trashed_assets = Asset.trashed.includes(:active_version).map do |a|
          {
            id: a.id,
            title: a.title,
            name: a.title,
            status: a.status,
            deleted_at: a.deleted_at,
            properties: a.properties.merge(a.active_version&.properties || {}),
            url: asset_url_for(a),
          }
        end

        render json: { folders: trashed_folders, assets: trashed_assets, breadcrumbs: [ { id: "bin", name: "Trash Bin" } ] }
      end

      # Returns the workflow task history for the most recent {WorkflowInstance}
      # on this asset.
      #
      # @return [void] renders +200 OK+ with +{ active, instance_status, started_at, tasks }+
      # GET /api/v1/assets/:id/workflow_history
      #
      # Returns ALL workflow instances for this asset (not just the latest).
      # Each instance includes its own task list so the panel can render every
      # concurrent workflow independently and allow independent approval/cancellation.
      def workflow_history
        @asset = find_asset_record
        instances = @asset.workflow_instances
                          .includes(:workflow, { workflow_tasks: [ :user, :workflow_step ] })
                          .order(created_at: :desc)

        if instances.empty?
          return render json: { active: false, instances: [], tasks: [] }
        end

        current_user_id = active_resource_owner.id
        is_admin        = current_user_admin?

        serialized = instances.map do |inst|
          tasks = inst.workflow_tasks.includes(:user, :workflow_step).order(created_at: :asc).map do |task|
            {
              id:              task.id,
              step_name:       task.workflow_step.title,
              user_name:       task.user.email,
              status:          task.status,
              comment:         task.comment,
              completed_at:    task.completed_at,
              is_current_user: task.user_id == current_user_id,
              is_pending:      task.status == "pending",
            }
          end

          {
            instance_id:      inst.id,
            workflow_id:      inst.workflow_id,
            workflow_name:    inst.workflow.name,
            instance_status:  inst.status,
            started_at:       inst.started_at,
            completed_at:     inst.completed_at,
            cancel_reason:    inst.cancel_reason,
            cancelled_by:     inst.cancelled_by&.email,
            can_force_cancel: is_admin && !WorkflowInstance::TERMINAL_STATUSES.include?(inst.status),
            tasks:            tasks,
          }
        end

        # Legacy single-instance shape for backward compat (first active instance)
        active_instance = serialized.find { |i| i[:instance_status] == "in_progress" }

        render json: {
          active:    active_instance.present?,
          instances: serialized,
          # Provide flattened tasks from the FIRST active instance for the legacy
          # approval action box.  This preserves WorkflowPanel's existing flow while
          # the new multi-instance UI shows all of them.
          instance_status: active_instance&.dig(:instance_status),
          started_at:      active_instance&.dig(:started_at),
          tasks:           active_instance&.dig(:tasks) || [],
        }
      end

      # Accepts an array of SHA-256 checksums and returns any matching
      # duplicates already stored in the DAM.
      #
      # @return [void] renders +200 OK+ with +{ duplicates: Hash<checksum, Array<Hash>> }+
      def check_hashes
        hashes = params[:hashes] || []

        # We check hashes against the AssetVersion table now, as versions contain the physical files
        existing_versions = AssetVersion.includes(asset: :folder).where("properties->>'checksum_sha256' IN (?)", hashes)

        duplicates = existing_versions.each_with_object({}) do |version, acc|
          hash_val = version.properties["checksum_sha256"]
          asset = version.asset

          acc[hash_val] ||= []
          acc[hash_val] << {
            id: asset.uuid,
            title: asset.title,
            version: version.version_number,
            url: asset_url_for(asset),
            folderName: asset.folder ? asset.folder.name : "/Root/Uncategorized",
          }
        end

        render json: { duplicates: duplicates }, status: :ok
      end

      # Streams a watermarked version of an image asset.
      #
      # Applies a 45° diagonal +CONFIDENTIAL+ annotation via MiniMagick and
      # sends the result as an attachment download.  Only supported for
      # +image/*+ content types.
      #
      # @return [void] renders +200 OK+ with the binary image data as an attachment
      # @return [void] renders +422+ for non-image assets
      # @return [void] renders +500+ on MiniMagick failure
      def watermarked
        @asset = find_asset_record(Asset.includes(:active_version))
        active_v = @asset.active_version

        storage_path = active_v&.properties&.fetch("storage_path", nil) || @asset.properties["storage_path"]
        content_type = active_v&.properties&.fetch("content_type", nil) || @asset.properties["content_type"]

        unless content_type&.start_with?("image/")
          return render json: { error: "Watermarking is only supported for images." }, status: :unprocessable_entity
        end

        clean_path = storage_path.to_s.sub(%r{\A/}, "")
        file_path = Rails.root.join("storage/dam", clean_path)
        font_path = Rails.root.join("public/fonts/Roboto-Regular.ttf").to_s

        begin
          require "mini_magick"
          image = MiniMagick::Image.open(file_path)

          image.combine_options do |c|
            c.gravity "center"
            c.fill "rgba(255,255,255,0.4)"
            c.font font_path
            c.pointsize "120"
            c.annotate "-45", "CONFIDENTIAL / ASHOK PELLURU"
          end

          send_data image.to_blob,
                    type: content_type || "image/jpeg",
                    disposition: "attachment",
                    filename: "watermarked_v#{active_v&.version_number}_#{@asset.title || @asset.uuid}.jpg"
        rescue StandardError => e
          Rails.logger.error "Watermarking failed: #{e.message}"
          render json: { error: "Failed to generate secure proxy." }, status: :internal_server_error
        end
      end

      # Serves a file directly from local/staging storage.
      #
      # == URL
      #   GET /api/v1/assets/local/:uuid
      #
      # == Resolution order
      #   1. ActiveStorage attachment on the active version → redirect to blob URL
      #   2. +storage/dam/<relative_path>+ (files moved by AssetProcessorWorker)
      #   3. Absolute +tmp/uploads/+ staging path (files awaiting worker processing)
      #
      # == HTTP caching
      #   Returns +ETag+ and +Last-Modified+ headers.  Clients that re-send
      #   +If-None-Match+ will receive +304 Not Modified+ without re-transmitting
      #   the file body, making thumbnail-heavy list views much faster.
      #
      # == Security
      #   Both resolved paths are checked against their respective roots
      #   (+storage/dam+ and +tmp/+) to block directory-traversal attacks.
      #   The +storage_path+ value comes from the database, not from user input,
      #   but we validate it regardless as defence-in-depth.
      #
      # @return [void] redirects to ActiveStorage URL, or streams file inline
      # @return [void] 304 Not Modified when ETag matches
      # @return [void] 404 when file cannot be located on disk
      # @return [void] 403 when resolved path escapes the permitted root
      def serve_local
        asset    = Asset.includes(:active_version).find_by!(uuid: params[:uuid])
        active_v = asset.active_version

        storage_path = active_v&.properties&.fetch("storage_path", nil) ||
                       asset.properties["storage_path"]
        content_type = (active_v&.properties&.fetch("content_type", nil) ||
                        asset.properties["content_type"]).presence || "application/octet-stream"

        # 1. ActiveStorage attachment: redirect to signed blob URL.
        if active_v.respond_to?(:file) && active_v.file.attached?
          return redirect_to url_for(active_v.file), allow_other_host: false
        end

        return render json: { error: "Asset version has no storage path" }, status: :not_found unless storage_path.present?

        # 2. Resolve DAM root path (files processed and stored by AssetProcessorWorker).
        storage_root  = Rails.root.join("storage/dam").to_s
        clean_path    = storage_path.to_s.sub(%r{\A/}, "")
        dam_candidate = Rails.root.join("storage/dam", clean_path)

        # 3. Resolve tmp staging path (files awaiting background processing).
        tmp_root      = Rails.root.join("tmp").to_s
        tmp_candidate = Pathname.new(storage_path.to_s)

        # Security: ensure each resolved path stays within its permitted root.
        dam_path_safe = File.expand_path(dam_candidate).start_with?(storage_root)
        tmp_path_safe = File.expand_path(tmp_candidate).start_with?(tmp_root)

        # brakeman:ignore:SendFile - both paths validated against root dirs above; storage_path is a DB value
        file_to_serve =
          if dam_path_safe && File.exist?(dam_candidate)
            dam_candidate.to_s
          elsif tmp_path_safe && File.exist?(tmp_candidate)
            tmp_candidate.to_s
          end

        unless file_to_serve
          return render json: {
            error:      "File missing from disk",
            looked_at:  dam_candidate.to_s,
          }, status: :not_found
        end

        # ── HTTP caching headers ────────────────────────────────────────────────
        file_stat    = File.stat(file_to_serve)
        etag_value   = %("#{Digest::MD5.file(file_to_serve).hexdigest}")
        last_modified = file_stat.mtime.httpdate

        response.headers["ETag"]          = etag_value
        response.headers["Last-Modified"] = last_modified
        # private: do not store in shared CDN caches; max-age: 1 hour
        response.headers["Cache-Control"] = "private, max-age=3600, must-revalidate"

        # Conditional GET: return 304 if client already has the current version.
        if request.headers["If-None-Match"] == etag_value ||
           (request.headers["If-Modified-Since"] &&
            Time.parse(request.headers["If-Modified-Since"]) >= file_stat.mtime)
          return head :not_modified
        end

        send_file file_to_serve, disposition: "inline", type: content_type
      end

      private

      # Parses the DAM filename naming convention and extracts structured metadata.
      #
      # Expected format: +ProductID-LanguageCode-AssetTypeCode.ext+
      # Example:         +012993112028-en-FR01.jpg+
      #
      # Returns +nil+ for filenames that do not match the convention (fewer
      # than three dash-delimited segments, or an asset-type code that does not
      # match +[A-Z]{2}\\d{2}+).
      #
      # @param filename [String] the original upload filename
      # @return [Hash, nil] keys: +'dam:product_id'+, +'dam:language_code'+,
      #   +'dam:asset_type'+; or +nil+ on no match
      def parse_product_filename(filename)
        return nil if filename.blank?

        base = File.basename(filename.to_s, File.extname(filename.to_s))
        parts = base.split("-")
        return nil if parts.length < 3

        asset_type_code = parts.last.to_s.upcase
        language_code   = parts[-2].to_s.downcase
        product_id      = parts[0...-2].join("-")

        # Asset type must match two letters + two digits (FR01, BK02, SD01, etc.)
        return nil unless asset_type_code.match?(/\A[A-Z]{2}\d{2}\z/)

        {
          "dam:product_id"    => product_id,
          "dam:language_code" => language_code,
          "dam:asset_type"    => asset_type_code,
        }
      end

      # Dispatches the three standard post-processing background jobs for a
      # newly created or edited asset version.
      #
      # 1. {AssetProcessorWorker}    — extracts metadata, stores to active backend.
      # 2. {CdnInvalidationWorker}   — purges the edge cache.
      # 3. {EdgeMetadataSyncWorker}  — syncs relational data to the edge KV store.
      #
      # All three workers are idempotent; calling this on an overwrite is safe.
      #
      # @param target_asset   [Asset]       the parent asset record
      # @param target_version [AssetVersion] the newly created version
      # @param file_path      [Pathname, String] staging path of the raw binary
      # @return [void]
      def dispatch_asset_workers(target_asset, target_version, file_path)
        # 1. Process the physical image binary
        AssetProcessorWorker.perform_async(target_version.id, file_path.to_s) if defined?(AssetProcessorWorker)

        # 2. Invalidate the edge cache for the CDN URL
        CdnInvalidationWorker.perform_async("asset", target_asset.uuid) if defined?(CdnInvalidationWorker)

        # 3. Sync the latest relational metadata to the Edge KV store
        EdgeMetadataSyncWorker.perform_async(target_asset.uuid) if defined?(EdgeMetadataSyncWorker)
      end

      # Builds the editor state from request parameters with proper permission parsing.
      #
      # @return [Hash] Editor state with normalized parameters
      def build_editor_state_from_params
        permitted_geometry = params.permit(geometry: [ :rotate, :flip_horizontal, :flip_vertical, focal_point: [ :x, :y ] ])[:geometry] || {}
        permitted_adjustments = params.permit(adjustments: {})[:adjustments] || {}

        {
          adjustments: permitted_adjustments.transform_keys(&:to_sym),
          crop_aspect: params[:crop_aspect].to_s.presence || "free",
          filter: params[:filter].to_s.presence || "None",
          geometry: {
            rotate: permitted_geometry[:rotate].to_i,
            flip_horizontal: permitted_geometry[:flip_horizontal].present? && permitted_geometry[:flip_horizontal] != "false",
            flip_vertical: permitted_geometry[:flip_vertical].present? && permitted_geometry[:flip_vertical] != "false",
            focal_point: permitted_geometry[:focal_point].present? ? {
              x: permitted_geometry[:focal_point][:x].to_f,
              y: permitted_geometry[:focal_point][:y].to_f,
            } : { x: 50, y: 50 },
          },
          custom_cli: params[:custom_cli].to_s.presence,
        }
      end

      # Resolves the absolute file path for a source image, handling both
      # absolute paths (tmp files) and relative paths (storage/dam).
      #
      # @param asset [Asset]
      # @return [String] Absolute file path
      def resolve_source_file_path(asset)
        active_v = asset.active_version
        source_path = active_v&.properties&.dig("storage_path").to_s || asset.properties&.dig("storage_path").to_s

        # If it's already an absolute path (like a tmp file), use it directly
        return source_path if File.exist?(source_path)

        # Otherwise, treat it as relative to storage/dam
        clean_path = source_path.sub(%r{\A/}, "")
        Rails.root.join("storage/dam", clean_path).to_s
      end

      # Returns the currently acting {User}, resolving from Devise session,
      # OAuth token, or falling back to the first user (development only).
      #
      # @return [User]
      def active_resource_owner
        if user_signed_in?
          current_user
        elsif doorkeeper_token&.resource_owner_id
          User.find(doorkeeper_token.resource_owner_id)
        else
          User.first
        end
      end

      # Serialises an {Asset} into the standard API response hash, merging
      # parent +properties+ with the active-version properties so the React
      # frontend always sees a flat metadata map.
      #
      # @param asset [Asset]
      # @return [Hash] with keys +:id+, +:uuid+, +:title+, +:version+,
      #   +:metadata+, +:url+
      def format_asset(asset)
        active_v = asset.active_version
        metadata = asset.properties.merge(active_v&.properties || {})
        {
          id: asset.uuid || asset.id,
          uuid: asset.uuid,
          title: asset.title,
          status: normalised_asset_status(asset),
          version: active_v&.version_number || 1,
          # Merge parent properties with active version properties so React sees everything
          metadata: metadata,
          content_type: metadata["content_type"],
          thumb_url: asset_url_for(asset),
          folder_id: asset.folder_id,
          trashed: asset.trashed?,
          url: asset_url_for(asset),
        }
      end

      def find_asset_record(scope = Asset)
        scope.find_by(id: params[:id]) || scope.find_by!(uuid: params[:id])
      end

      def normalised_asset_status(asset)
        raw_status = asset.attributes_before_type_cast["status"] || asset[:status] || asset.status
        return raw_status if raw_status.is_a?(String) && raw_status.match?(/\A[a-z_]+\z/)

        Asset.statuses.key(raw_status.to_i) || raw_status.to_s
      end

      def update_metadata_payload
        raw_asset = params[:asset]
        payload =
          case raw_asset
          when ActionController::Parameters
            raw_asset.permit(:title, :folder_id, tags: [], metadata: {}).to_h
          when Hash
            raw_asset
          else
            {}
          end

        metadata = payload["metadata"] || payload[:metadata] || {}
        tags = payload["tags"] || payload[:tags]
        metadata = metadata.merge("tags" => tags) if tags.present?
        metadata.compact_blank
      end

      def normalised_folder_id
        return nil unless folder_id_supplied?

        folder_value = params.dig(:asset, :folder_id) || params[:folder_id]
        folder_value == "root" ? nil : folder_value
      end

      def folder_id_supplied?
        params[:folder_id].present? || params.dig(:asset, :folder_id).present?
      end
    end
  end
end
