module Api
  module V1
    class FoldersController < ApplicationController
      include AssetUrlHelper
      before_action :authenticate_user!

      def index
        @active_view = 'All Assets'
        # 1. Fetch all active folders in ONE query
        all_folders = Folder.active.to_a

        # 2. Create a fast lookup dictionary (Hash) by ID
        folder_dict = all_folders.index_by(&:id)

        # 3. Build the full path for each folder in memory
        formatted_folders = all_folders.map do |folder|
          path_names = []
          current = folder

          # Walk up the tree using the dictionary
          while current
            path_names.unshift(current.name)
            current = folder_dict[current.parent_id]
          end

          # Format for the React frontend
          {
            id: folder.id,
            name: "/" + path_names.join("/") # e.g., "/Marketing/2026/Campaigns"
          }
        end

        # 4. Sort alphabetically so child folders naturally group under their parents
        formatted_folders.sort_by! { |f| f[:name].downcase }

        render json: { folders: formatted_folders }
      end

      def show
        if params[:id] == 'root'
          # Strictly fetch only ACTIVE top-level items
          @folders = Folder.active.where(parent_id: nil)

          #  FIX 1: Eager load the active_version to prevent database N+1 performance issues
          @assets = Asset.active.where(folder_id: nil).includes(:active_version)

          breadcrumbs = [{ id: 'root', name: 'Home' }]
        else
          # Ensure a user cannot hack the URL to view a deleted folder
          current_folder = Folder.active.find(params[:id])

          # Filter subfolders and assets by active scope
          @folders = Folder.active.where(parent_id: current_folder.id)

          #  FIX 1: Eager load the active_version
          @assets = Asset.active.where(folder_id: current_folder.id).includes(:active_version)

          breadcrumbs = build_breadcrumbs(current_folder)
        end

        render json: {
          folders: @folders,
          assets: @assets.map { |asset| format_asset_payload(asset) },
          breadcrumbs: breadcrumbs
        }
      end

      def create
        @folder = current_user.folders.build(folder_params)
        # Handle the 'root' case from JS
        @folder.parent_id = nil if params[:folder][:parent_id] == 'root'

        if @folder.save
          render json: @folder, status: :created
        else
          render json: { errors: @folder.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/folders/:id/purge_cdn
      def purge_folder_cdn
        CdnInvalidationWorker.perform_async('folder', params[:id])
        render json: { message: "Folder CDN purge initiated." }, status: :ok
      end

      # DELETE /api/v1/folders/:id (Soft Delete)
      def destroy
        @folder = Folder.find(params[:id])
        @folder.soft_delete

        # Auto-purge CDN: Instantly drop deprecated assets from edge nodes
        CdnInvalidationWorker.perform_async('folder', @folder.id)
        render json: { success: true, message: "Folder moved to bin" }
      end

      # POST /api/v1/folders/:id/restore
      def restore
        @folder = Folder.trashed.find(params[:id])
        @folder.restore
        render json: { success: true, message: "Folder restored" }
      end

      # GET /api/v1/folders/:id/schema
      # Returns the schema currently applied to a folder (or inherited from ancestors).
      def schema
        folder_id = params[:id] == 'root' ? nil : params[:id]

        assignment = find_schema_assignment(folder_id)

        if assignment
          s = MetadataSchema.active.find_by(id: assignment.metadata_schema_id)
          render json: { schema: s ? serialize_schema(s) : nil, source: assignment_source(folder_id, assignment) }
        else
          render json: { schema: nil, source: 'none' }
        end
      end

      # POST /api/v1/folders/:id/apply_schema
      # Queues a background job to apply schema to folder + assets.
      def apply_schema
        schema = MetadataSchema.active.find_by(id: params[:schema_id])
        return render json: { error: 'Schema not found' }, status: :not_found unless schema

        folder_id = params[:id] == 'root' ? nil : params[:id]
        cascade   = params[:cascade] != 'false'

        ApplySchemaToFolderJob.perform_later(
          folder_id:    folder_id.to_s,
          schema_id:    schema.id,
          cascade:      cascade,
          initiated_by: current_user&.id
        )

        render json: {
          message: "Schema '#{schema.name}' is being applied. Assets will update shortly.",
          schema_id:   schema.id,
          schema_name: schema.name,
          cascade:     cascade
        }, status: :accepted
      end

      # DELETE /api/v1/folders/:id/remove_schema
      # Removes the schema assignment from a folder.
      def remove_schema
        folder_id = params[:id] == 'root' ? nil : params[:id]
        MetadataSchemaFolderAssignment.where(folder_id: folder_id.to_s).destroy_all
        render json: { message: 'Schema assignment removed.' }, status: :ok
      end

      # DELETE /api/v1/folders/:id/permanent
      def permanent_delete
        @folder = Folder.trashed.find(params[:id])

        # Auto-purge CDN: Ensure edge nodes drop these files permanently
        CdnInvalidationWorker.perform_async('folder', @folder.id)

        # Note: If deleting a folder should also permanently delete all assets inside it,
        # you need `dependent: :destroy` on your Folder model's `has_many :assets` association.
        @folder.destroy
        render json: { success: true, message: "Folder permanently deleted" }
      end

      private

      # Helper to standardize the asset payload structure for React
      def format_asset_payload(asset)
        active_v = asset.active_version

        {
          id: asset.id, # Using the primary DB ID to match your editor fix
          uuid: asset.uuid,
          title: asset.title,
          name: asset.title,
          status: asset.status || 'draft',
          version: active_v&.version_number || 1,

          properties: asset.properties.merge(active_v&.properties || {}),

          url: asset_url_for(asset)
        }
      end

      def build_breadcrumbs(folder)
        crumbs = []
        current = folder

        # Walk up the tree until there are no more parents
        while current
          crumbs.unshift({ id: current.id, name: current.name })
          current = Folder.active.find_by(id: current.parent_id)
        end

        # Prepend the Home root
        crumbs.unshift({ id: 'root', name: 'Home' })
        crumbs
      end

      def folder_params
        params.require(:folder).permit(:name, :parent_id)
      end

      # ── Schema helpers ──────────────────────────────────────────────────────
      def find_schema_assignment(folder_id)
        # First check direct assignment
        direct = MetadataSchemaFolderAssignment.find_by(folder_id: folder_id.to_s)
        return direct if direct

        # Walk up folder tree to find inherited assignment
        return nil if folder_id.blank?
        folder = Folder.active.find_by(id: folder_id)
        while folder&.parent_id
          parent_assignment = MetadataSchemaFolderAssignment.find_by(folder_id: folder.parent_id.to_s)
          return parent_assignment if parent_assignment
          folder = Folder.active.find_by(id: folder.parent_id)
        end
        nil
      end

      def assignment_source(folder_id, assignment)
        assignment.folder_id.to_s == folder_id.to_s ? 'direct' : 'inherited'
      end

      def serialize_schema(schema)
        {
          id:          schema.id,
          name:        schema.name,
          slug:        schema.slug,
          level:       schema.level,
          description: schema.description,
          is_builtin:  schema.is_builtin,
          tabs:        schema.tabs || []
        }
      end
    end
  end
end