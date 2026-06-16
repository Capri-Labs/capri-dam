module Api
  module V1
    class AssetsController < ApplicationController
      include AssetUrlHelper
      wrap_parameters format: []

      protect_from_forgery with: :null_session, if: -> { request.format.json? || doorkeeper_token.present? }
      before_action :authenticate_hybrid!

      # GET /api/v1/search
      def search
        @assets = Asset.where(status: 'ready').includes(:active_version)

        if params[:q].present?
          @assets = @assets.where("title ILIKE ?", "%#{params[:q]}%")
        end

        if params[:format].present?
          # Search top-level asset properties or active version properties
          @assets = @assets.where("properties ->> 'format' = ?", params[:format])
        end

        render json: {
          total: @assets.count,
          results: @assets.map { |asset| format_asset(asset) }
        }
      end

      # POST /api/v1/assets
      def create
        file = params[:file]
        target_folder = params[:folder_id].present? ? Folder.find_by(id: params[:folder_id]) : nil

        if file.respond_to?(:path)
          ActiveRecord::Base.transaction do
            # 1. Create the Parent Asset
            @asset = Asset.create!(
              user: active_resource_owner,
              folder: target_folder,
              title: params[:title] || file.original_filename,
              status: 'pending',
              uuid: SecureRandom.uuid,
              properties: { original_filename: file.original_filename }
            )

            # 2. Create the Initial Immutable Version (V1)
            @version = @asset.asset_versions.build(
              version_number: 1,
              action_type: 'initial_upload',
              created_by_id: active_resource_owner&.id,
              properties: {
                content_type: file.content_type,
                size: file.size
              }
            )

            # Attach the file using ActiveStorage (if configured)
            @version.file.attach(file) if @version.respond_to?(:file)
            @version.save!

            # 3. Set the active pointer
            @asset.update!(active_version_id: @version.id)

            # 4. Handle Local/Staging Path Logic for your Worker
            staging_path = Rails.root.join('tmp', 'uploads', "#{@asset.uuid}_v1_#{file.original_filename}")
            FileUtils.mkdir_p(File.dirname(staging_path))
            FileUtils.cp(file.path, staging_path)

            @version.update!(properties: @version.properties.merge('storage_path' => staging_path.to_s))

            # Trigger the worker (Ensure your worker updates the version's storage_path when done)
            AssetProcessorWorker.perform_async(@version.id, staging_path.to_s)
          end

          render json: { id: @asset.uuid, status: 'processing' }, status: :accepted
        else
          render json: { error: "No file provided" }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/assets/:id/versions
      def versions
        # 🚀 FIX: Use find_by!(uuid: params[:id]) instead of find()
        @asset = Asset.includes(asset_versions: :created_by).find(params[:id])

        history = @asset.asset_versions.order(version_number: :desc).map do |v|
          {
            id: v.id,
            version_number: v.version_number,
            action_type: v.action_type.to_s.titleize,
            created_at: v.created_at.strftime("%b %d, %Y at %I:%M %p"),
            created_by: v.created_by&.email || 'System User',
            is_active: @asset.active_version_id == v.id,
            size: v.properties['size'] ? "#{(v.properties['size'].to_i / 1024.0 / 1024.0).round(2)} MB" : 'Unknown'
          }
        end

        render json: { versions: history }, status: :ok
      end

      # POST /api/v1/assets/:id/versions/:version_id/restore
      def restore_version
        @asset = Asset.find(params[:id])

        # version_id is the standard database ID, so standard find() is safe here
        @version = @asset.asset_versions.find(params[:version_id])

        @asset.update!(active_version_id: @version.id)

        render json: format_asset(@asset), status: :ok
      end

      # POST /api/v1/assets/:id/process_image
      def process_image
        @asset = Asset.find(params[:id])
        return render json: { error: "Asset not found." }, status: :not_found if @asset.nil?

        editor_state = {
          adjustments: params[:adjustments] || {},
          crop_aspect: params[:crop_aspect],
          filter: params[:filter],
          geometry: params.permit(geometry: [:rotate, :flip_horizontal, focal_point: [:x, :y]])[:geometry] || {},
          custom_cli: params[:custom_cli]
        }

        active_v = @asset.active_version
        base_properties = active_v&.properties || @asset.properties || {}

        new_version_props = base_properties.deep_dup
        #new_version_props['editor_state'] = editor_state
        new_version_props['editor_state'] = {
          adjustments: {},
          crop_aspect: 'free',
          filter: 'None',
          geometry: { focal_point: editor_state[:geometry][:focal_point] || { x: 50, y: 50 } }
        }

        # ==========================================
        # 🚀 PHYSICAL IMAGE BAKING PIPELINE
        # ==========================================
        source_path = base_properties['storage_path'].to_s

        # 🚀 SMART PATH RESOLUTION:
        # Check if it's already a valid absolute path first (like a tmp file).
        # If not, assume it's a relative path from the DAM root.
        file_path = if File.exist?(source_path)
                      source_path
                    else
                      clean_path = source_path.sub(%r{\A/}, '')
                      Rails.root.join('storage/dam', clean_path).to_s
                    end

        # Fail gracefully if the physical file is totally missing from disk
        unless File.exist?(file_path)
          return render json: { error: "Source file not found on disk." }, status: :unprocessable_entity
        end

        new_file_tmp_path = Rails.root.join('tmp', "baked_#{@asset.uuid}_#{SecureRandom.hex(4)}.jpg")

        require 'mini_magick'
        image = MiniMagick::Image.open(file_path)

        image.combine_options do |cmd|
          # 1. Bake Geometry
          cmd.flop if editor_state[:geometry][:flip_horizontal]
          cmd.rotate(editor_state[:geometry][:rotate].to_s) if editor_state[:geometry][:rotate].to_i != 0

          # 2. Bake Lighting
          b = editor_state[:adjustments][:brightness].to_i
          c = editor_state[:adjustments][:contrast].to_i
          cmd.brightness_contrast "#{b}x#{c}" if b != 0 || c != 0

          s = editor_state[:adjustments][:saturation].to_i
          cmd.modulate "100,#{100 + s},100" if s != 0

          # 🚀 3. FULL POWER: Inject raw ImageMagick commands
          if editor_state[:custom_cli].present?
            # Splits commands like "-monochrome -charcoal 2" and injects them
            editor_state[:custom_cli].scan(/-[a-z]+[^-]*/).each do |arg|
              cmd << arg.strip
            end
          end

        end

        image.write(new_file_tmp_path)

        new_version_props['storage_path'] = new_file_tmp_path.to_s
        new_version_props['file_size'] = File.size(new_file_tmp_path)
        # ==========================================

        ActiveRecord::Base.transaction do
          # Safely resolve the target folder
          target_folder_id = params[:target_folder_id] == 'root' ? nil : params[:target_folder_id]

          # Detect if the user is attempting to save to a different folder
          is_moving = params[:target_folder_id].present? && target_folder_id != @asset.folder_id

          case params[:save_mode]
          when 'new'
            # 🚀 MODE 1: FORK (Save as Copy from UI)
            # BEHAVIOR: Original stays at V5 in Folder A. New Copy is created at V5 in Folder B.
            folder_id_for_copy = params[:target_folder_id].present? ? target_folder_id : @asset.folder_id

            @new_asset = Asset.create!(
              user: active_resource_owner,
              folder_id: folder_id_for_copy,
              title: "#{@asset.title} (Copy)",
              status: 'ready',
              uuid: SecureRandom.uuid,
              properties: @asset.properties.deep_dup
            )

            # Inherit the exact version number of the parent to maintain parity
            current_version_num = active_v&.version_number || 1

            @new_version = @new_asset.asset_versions.create!(
              version_number: current_version_num,
              action_type: 'cloned_edit',
              created_by_id: active_resource_owner&.id,
              properties: new_version_props
            )

            @new_asset.update!(active_version_id: @new_version.id)
            AssetProcessorWorker.perform_async(@new_version.id, new_file_tmp_path.to_s) if defined?(AssetProcessorWorker)

            render json: format_asset(@new_asset), status: :created

          when 'overwrite'
            # 🚀 MODE 2: DESTRUCTIVE (Overwrite Current)
            # BEHAVIOR: Bakes new file into the existing version row.
            if active_v.present?
              active_v.update!(properties: new_version_props)
              AssetProcessorWorker.perform_async(active_v.id, new_file_tmp_path.to_s) if defined?(AssetProcessorWorker)
            else
              @new_version = @asset.asset_versions.create!(
                version_number: 1,
                action_type: 'image_edit',
                created_by_id: active_resource_owner&.id,
                properties: new_version_props
              )
              @asset.update!(active_version_id: @new_version.id)
              AssetProcessorWorker.perform_async(@new_version.id, new_file_tmp_path.to_s) if defined?(AssetProcessorWorker)
            end

            # If a folder was selected during an overwrite, move the existing asset
            @asset.update!(folder_id: target_folder_id) if is_moving

            render json: format_asset(@asset), status: :ok

          when 'version'
            # 🚀 MODE 3: BRANCH (Save as New Version from UI)
            new_version_num = @asset.next_version_number

            if is_moving
              # BEHAVIOR: Original stays at V5 in Folder A. New Asset is created at V6 in Folder B.
              @new_asset = Asset.create!(
                user: active_resource_owner,
                folder_id: target_folder_id,
                title: @asset.title,
                status: 'ready',
                uuid: SecureRandom.uuid,
                properties: @asset.properties.deep_dup
              )

              @new_version = @new_asset.asset_versions.create!(
                version_number: new_version_num, # Bumps to V6
                action_type: 'branched_edit',
                created_by_id: active_resource_owner&.id,
                properties: new_version_props
              )

              @new_asset.update!(active_version_id: @new_version.id)
              AssetProcessorWorker.perform_async(@new_version.id, new_file_tmp_path.to_s) if defined?(AssetProcessorWorker)

              render json: format_asset(@new_asset), status: :created
            else
              # BEHAVIOR: Standard bump to V6 inside the current folder.
              @new_version = @asset.asset_versions.create!(
                version_number: new_version_num,
                action_type: 'image_edit',
                created_by_id: active_resource_owner&.id,
                properties: new_version_props
              )

              @asset.update!(active_version_id: @new_version.id)
              AssetProcessorWorker.perform_async(@new_version.id, new_file_tmp_path.to_s) if defined?(AssetProcessorWorker)

              render json: format_asset(@asset), status: :ok
            end
          end
        end
      end

      # DELETE /api/v1/assets/:id
      def destroy
        @asset = Asset.find(params[:id])
        @asset.soft_delete
        render json: { success: true, message: "Moved to bin" }
      end

      # POST /api/v1/assets/:id/restore
      def restore
        @asset = Asset.trashed.find(params[:id])
        @asset.restore
        render json: { success: true, message: "Asset restored" }
      end

      # DELETE /api/v1/assets/:id/permanent
      def permanent_delete
        @asset = Asset.trashed.includes(:asset_versions).find(params[:id])

        # 1. Loop through ALL versions to delete physical files
        backend = ::StorageBackend.find_by(active: true)
        storage = ::StorageManager.adapter_for(backend) if backend

        @asset.asset_versions.each do |version|
          storage_path = version.properties['storage_path']
          storage.delete(storage_path) if storage && storage_path

          # If using ActiveStorage
          version.file.purge if version.respond_to?(:file) && version.file.attached?
        end

        # 2. Destroy database record (cascades to versions)
        @asset.destroy
        render json: { success: true, message: "Permanently deleted all versions" }
      end

      # GET /api/v1/bin
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
            url: asset_url_for(a)
          }
        end

        render json: { folders: trashed_folders, assets: trashed_assets, breadcrumbs: [{ id: 'bin', name: 'Trash Bin' }] }
      end

      # GET /api/v1/assets/:id/workflow_history
      def workflow_history
        @asset = Asset.find(params[:id])
        instance = @asset.workflow_instances.order(created_at: :desc).first

        if instance
          tasks = instance.workflow_tasks.includes(:user, :workflow_step).order(created_at: :asc)
          history = tasks.map do |task|
            {
              id: task.id,
              step_name: task.workflow_step.title,
              user_name: task.user.email,
              status: task.status,
              comment: task.comment,
              completed_at: task.completed_at,
              is_current_user: task.user_id == active_resource_owner.id,
              is_pending: task.status == 'pending'
            }
          end
          render json: { active: true, instance_status: instance.status, started_at: instance.started_at, tasks: history }
        else
          render json: { active: false, tasks: [] }
        end
      end

      # POST /api/v1/assets/check_hashes
      def check_hashes
        hashes = params[:hashes] || []

        # We check hashes against the AssetVersion table now, as versions contain the physical files
        existing_versions = AssetVersion.includes(asset: :folder).where("properties->>'checksum_sha256' IN (?)", hashes)

        duplicates = existing_versions.each_with_object({}) do |version, acc|
          hash_val = version.properties['checksum_sha256']
          asset = version.asset

          acc[hash_val] ||= []
          acc[hash_val] << {
            id: asset.uuid,
            title: asset.title,
            version: version.version_number,
            url: asset_url_for(asset),
            folderName: asset.folder ? asset.folder.name : '/Root/Uncategorized'
          }
        end

        render json: { duplicates: duplicates }, status: :ok
      end

      # GET /api/v1/assets/:id/watermarked
      def watermarked
        @asset = Asset.includes(:active_version).find(params[:id])
        active_v = @asset.active_version

        storage_path = active_v&.properties&.fetch('storage_path', nil) || @asset.properties['storage_path']
        content_type = active_v&.properties&.fetch('content_type', nil) || @asset.properties['content_type']

        unless content_type&.start_with?('image/')
          return render json: { error: "Watermarking is only supported for images." }, status: :unprocessable_entity
        end

        clean_path = storage_path.to_s.sub(%r{\A/}, '')
        file_path = Rails.root.join('storage/dam', clean_path)
        font_path = Rails.root.join('public', 'fonts', 'Roboto-Regular.ttf').to_s

        begin
          require 'mini_magick'
          image = MiniMagick::Image.open(file_path)

          image.combine_options do |c|
            c.gravity 'center'
            c.fill 'rgba(255,255,255,0.4)'
            c.font font_path
            c.pointsize '120'
            c.annotate '-45', 'CONFIDENTIAL / ASHOK PELLURU'
          end

          send_data image.to_blob,
                    type: content_type || 'image/jpeg',
                    disposition: 'attachment',
                    filename: "watermarked_v#{active_v&.version_number}_#{@asset.title || @asset.uuid}.jpg"
        rescue StandardError => e
          Rails.logger.error "Watermarking failed: #{e.message}"
          render json: { error: "Failed to generate secure proxy." }, status: :internal_server_error
        end
      end

      # GET /api/v1/assets/local/:uuid
      def serve_local
        asset = Asset.includes(:active_version).find_by!(uuid: params[:uuid])
        active_v = asset.active_version

        storage_path = active_v&.properties&.fetch('storage_path', nil) || asset.properties['storage_path']
        content_type = active_v&.properties&.fetch('content_type', nil) || asset.properties['content_type']

        if active_v.respond_to?(:file) && active_v.file.attached?
          return redirect_to url_for(active_v.file)
        end

        return render json: { error: "Asset version has no storage path" }, status: :not_found unless storage_path

        clean_path = storage_path.to_s.sub(%r{\A/}, '')
        physical_path = Rails.root.join("storage/dam", clean_path)

        # Check both physical and staging paths to be safe during worker transit
        if File.exist?(physical_path)
          send_file physical_path, disposition: 'inline', type: content_type
        elsif File.exist?(storage_path) # Direct fallback for tmp paths
          send_file storage_path, disposition: 'inline', type: content_type
        else
          render json: { error: "File missing from disk", looked_at: physical_path.to_s }, status: :not_found
        end
      end

      private

      def authenticate_hybrid!
        return if user_signed_in?
        doorkeeper_authorize!
      end

      def active_resource_owner
        if user_signed_in?
          current_user
        elsif doorkeeper_token&.resource_owner_id
          User.find(doorkeeper_token.resource_owner_id)
        else
          User.first
        end
      end

      def format_asset(asset)
        active_v = asset.active_version
        {
          id: asset.id,
          uuid: asset.uuid,
          title: asset.title,
          version: active_v&.version_number || 1,
          # Merge parent properties with active version properties so React sees everything
          metadata: asset.properties.merge(active_v&.properties || {}),
          url: asset_url_for(asset)
        }
      end
    end
  end
end