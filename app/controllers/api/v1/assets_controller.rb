module Api
  module V1
    # 1. CHANGE: Inherit from ApplicationController so it can read web cookies/CSRF
    class AssetsController < ApplicationController
      wrap_parameters format: []

      # 2. CHANGE: Protect from forgery (CSRF), but skip it if an API token is used
      protect_from_forgery with: :null_session, if: -> { request.format.json? || doorkeeper_token.present? }

      # 3. CHANGE: Use a custom dual-authentication method instead of strict Doorkeeper
      before_action :authenticate_hybrid!

      def search
        # 1. Base Query (Cloud Agnostic logic)
        @assets = Asset.where(status: 'ready')

        # 2. Filter by Title (Simple search)
        if params[:q].present?
          @assets = @assets.where("title ILIKE ?", "%#{params[:q]}%")
        end

        # 3. Filter by Metadata (JSONB Search)
        # Example: ?format=JPEG
        if params[:format].present?
          @assets = @assets.where("properties ->> 'format' = ?", params[:format])
        end

        # 4. Return JSON
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
          # 1. Create the Asset record
          asset = Asset.create!(
            user: active_resource_owner, # Updated helper method
            folder: target_folder,
            title: params[:title] || file.original_filename,
            status: 'pending',
            uuid: SecureRandom.uuid,
            properties: {
              content_type: file.content_type,
              original_filename: file.original_filename,
              size: file.size
            }
          )

          # 2. Save the file to a temporary "staging" area
          staging_path = Rails.root.join('tmp', 'uploads', "#{asset.uuid}_#{file.original_filename}")
          FileUtils.mkdir_p(File.dirname(staging_path))
          FileUtils.cp(file.path, staging_path)

          # 3. Trigger the worker with the staging path
          AssetProcessorWorker.perform_async(asset.id, staging_path.to_s)

          render json: { id: asset.uuid, status: 'processing' }, status: :accepted
        else
          render json: { error: "No file provided" }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/assets/:id
      # Moves to the Bin (Soft Delete)
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
      # Actually destroys the record and triggers ActiveStorage/Background jobs to delete the physical file
      def permanent_delete
        @asset = Asset.trashed.find(params[:id])

        # 1. Delete physical file from storage backend
        backend = ::StorageBackend.find_by(active: true)
        storage = ::StorageManager.adapter_for(backend)
        storage.delete(@asset.properties['storage_path']) if @asset.properties['storage_path']

        # 2. Destroy database record
        @asset.destroy
        render json: { success: true, message: "Permanently deleted" }
      end

      # GET /api/v1/bin
      # New endpoint to fetch everything currently in the trash
      def bin
        # Map out the trashed folders
        trashed_folders = Folder.trashed.map do |f|
          { id: f.id, name: f.name, deleted_at: f.deleted_at }
        end

        # Map out the trashed assets with properties intact
        trashed_assets = Asset.trashed.map do |a|
          {
            id: a.id,
            title: a.title,
            name: a.title,
            status: a.status,
            deleted_at: a.deleted_at,
            properties: a.properties, # <-- CRITICAL: Allows React to read content_type
            url: a.properties['storage_path'] ? "https://cdn.yourdam.com/assets/#{a.uuid}" : nil
          }
        end

        render json: {
          folders: trashed_folders,
          assets: trashed_assets,
          breadcrumbs: [{ id: 'bin', name: 'Trash Bin' }]
        }
      end

      # GET /api/v1/assets/:id/workflow_history
      def workflow_history
        @asset = Asset.find(params[:id])

        # Grab the most recent workflow instance for this asset
        instance = @asset.workflow_instances.order(created_at: :desc).first

        if instance
          # Fetch all tasks, ordered by creation time to build a timeline
          tasks = instance.workflow_tasks.includes(:user, :workflow_step).order(created_at: :asc)

          history = tasks.map do |task|
            {
              id: task.id,
              step_name: task.workflow_step.title,
              user_name: task.user.email, # Or task.user.full_name if you have that column
              status: task.status,
              comment: task.comment,
              completed_at: task.completed_at,
              # This boolean tells React if it should show the Approve/Reject buttons!
              is_current_user: task.user_id == active_resource_owner.id,
              is_pending: task.status == 'pending'
            }
          end

          render json: {
            active: true,
            instance_status: instance.status,
            started_at: instance.started_at,
            tasks: history
          }
        else
          render json: { active: false, tasks: [] }
        end
      end

      private

      # 4. CUSTOM AUTH: Check for web login first, then fallback to API token
      def authenticate_hybrid!
        return if user_signed_in? # Accept Devise web session

        doorkeeper_authorize! # Enforce OAuth token if not on web
      end

      # 5. CUSTOM OWNER: Grab the correct user regardless of how they logged in
      def active_resource_owner
        if user_signed_in?
          current_user
        elsif doorkeeper_token&.resource_owner_id
          User.find(doorkeeper_token.resource_owner_id)
        else
          # Fallback
          User.first
        end
      end

      def format_asset(asset)
        {
          id: asset.uuid,
          title: asset.title,
          metadata: asset.properties,
          url: "https://cdn.yourdam.com/assets/#{asset.uuid}?auto=webp"
        }
      end
    end
  end
end