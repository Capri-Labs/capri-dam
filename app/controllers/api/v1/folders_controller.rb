module Api
  module V1
    class FoldersController < ApplicationController
      include AssetUrlHelper
      before_action :authenticate_user!

      def index
        @active_view = "All Assets"
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
            name: "/" + path_names.join("/"), # e.g., "/Marketing/2026/Campaigns"
          }
        end

        # 4. Sort alphabetically so child folders naturally group under their parents
        formatted_folders.sort_by! { |f| f[:name].downcase }

        render json: { folders: formatted_folders }
      end

      def show
        if params[:id] == "root"
          # Strictly fetch only ACTIVE top-level items
          @folders = Folder.active.where(parent_id: nil)

          #  FIX 1: Eager load the active_version to prevent database N+1 performance issues
          @assets = Asset.active.where(folder_id: nil).includes(:active_version)

          breadcrumbs = [ { id: "root", name: "Home" } ]
        else
          # Ensure a user cannot hack the URL to view a deleted folder
          current_folder = Folder.active.find(params[:id])

          # Filter subfolders and assets by active scope
          @folders = Folder.active.where(parent_id: current_folder.id)

          #  FIX 1: Eager load the active_version
          @assets = Asset.active.where(folder_id: current_folder.id).includes(:active_version)

          breadcrumbs = build_breadcrumbs(current_folder)
        end

        # Apply optional sorting (sort + direction query params)
        folders_payload = sort_folders(@folders.map { |f| format_folder_payload(f) })
        assets_payload  = sort_assets(@assets.map { |asset| format_asset_payload(asset) })

        render json: {
          folders: folders_payload,
          assets: assets_payload,
          breadcrumbs: breadcrumbs,
          sort: { field: sort_field, direction: sort_direction },
        }
      end

      def create
        @folder = current_user.folders.build(folder_params)
        # Handle the 'root' case from JS
        @folder.parent_id = nil if params[:folder][:parent_id] == "root"

        if @folder.save
          render json: @folder, status: :created
        else
          render json: { errors: @folder.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/folders/:id (rename + description)
      def update
        @folder = Folder.active.find(params[:id])
        if @folder.update(folder_params)
          render json: {
            id:          @folder.id,
            name:        @folder.name,
            description: @folder.description,
            slug:        @folder.slug,
            updated_at:  @folder.updated_at,
          }
        else
          render json: { errors: @folder.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Folder not found" }, status: :not_found
      end

      # GET /api/v1/folders/:id/profiles
      # Returns the image profile, video profile, and metadata schema assigned to a folder.
      def profiles
        folder_id = params[:id]

        # Image profile
        img_assignment = ImageProfileFolderAssignment.find_by(folder_id: folder_id)
        image_profile  = img_assignment ? ImageProfile.active.find_by(id: img_assignment.image_profile_id) : nil

        # Video profile
        vid_assignment = VideoProfileFolderAssignment.find_by(folder_id: folder_id)
        video_profile  = vid_assignment ? VideoProfile.active.find_by(id: vid_assignment.video_profile_id) : nil

        # Metadata schema (direct or inherited)
        schema_assignment = find_schema_assignment(folder_id)
        schema = schema_assignment ? MetadataSchema.active.find_by(id: schema_assignment.metadata_schema_id) : nil

        # Folder policies (access)
        policies = FolderPolicy.where(folder_id: folder_id).includes(:user_group)

        render json: {
          image_profile: image_profile ? {
            id: image_profile.id, name: image_profile.name,
            crop_type: image_profile.crop_type,
            unsharp_mask: image_profile.effective_unsharp_mask,
            responsive_crop_enabled: image_profile.responsive_crop_enabled,
            swatch_enabled: image_profile.swatch_enabled
          } : nil,
          video_profile: video_profile ? {
            id: video_profile.id, name: video_profile.name,
            description: video_profile.description,
            encode_for_adaptive_streaming: video_profile.encode_for_adaptive_streaming,
            preset_count: video_profile.encoding_presets.size
          } : nil,
          metadata_schema: schema ? serialize_schema(schema).merge(source: assignment_source(folder_id, schema_assignment)) : nil,
          policies: policies.map { |p|
            {
              group_id:   p.user_group_id,
              group_name: p.user_group&.name,
              read:       p.read_access,
              write:      p.write_access,
              delete:     p.delete_access,
              manage:     p.manage_access,
              deny:       p.explicit_deny,
            }
          },
        }
      end
      def purge_folder_cdn
        CdnInvalidationWorker.perform_async("folder", params[:id])
        render json: { message: "Folder CDN purge initiated." }, status: :ok
      end

      # DELETE /api/v1/folders/:id (Soft Delete)
      def destroy
        @folder = Folder.find(params[:id])
        @folder.soft_delete

        # Auto-purge CDN: Instantly drop deprecated assets from edge nodes
        CdnInvalidationWorker.perform_async("folder", @folder.id)
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
        folder_id = params[:id] == "root" ? nil : params[:id]

        assignment = find_schema_assignment(folder_id)

        if assignment
          s = MetadataSchema.active.find_by(id: assignment.metadata_schema_id)
          render json: { schema: s ? serialize_schema(s) : nil, source: assignment_source(folder_id, assignment) }
        else
          render json: { schema: nil, source: "none" }
        end
      end

      # POST /api/v1/folders/:id/apply_schema
      # Queues a background job to apply schema to folder + assets.
      def apply_schema
        schema = MetadataSchema.active.find_by(id: params[:schema_id])
        return render json: { error: "Schema not found" }, status: :not_found unless schema

        folder_id = params[:id] == "root" ? nil : params[:id]
        cascade   = params[:cascade] != "false"

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
          cascade:     cascade,
        }, status: :accepted
      end

      # DELETE /api/v1/folders/:id/remove_schema
      # Removes the schema assignment from a folder.
      def remove_schema
        folder_id = params[:id] == "root" ? nil : params[:id]
        MetadataSchemaFolderAssignment.where(folder_id: folder_id.to_s).destroy_all
        render json: { message: "Schema assignment removed." }, status: :ok
      end

      # DELETE /api/v1/folders/:id/permanent
      def permanent_delete
        @folder = Folder.trashed.find(params[:id])

        # Auto-purge CDN: Ensure edge nodes drop these files permanently
        CdnInvalidationWorker.perform_async("folder", @folder.id)

        # Note: If deleting a folder should also permanently delete all assets inside it,
        # you need `dependent: :destroy` on your Folder model's `has_many :assets` association.
        @folder.destroy
        render json: { success: true, message: "Folder permanently deleted" }
      end

      private

      # Helper to standardize the asset payload structure for React
      def format_asset_payload(asset)
        active_v = asset.active_version

        merged_props = asset.properties.merge(active_v&.properties || {})

        {
          id: asset.id, # Using the primary DB ID to match your editor fix
          uuid: asset.uuid,
          title: asset.title,
          name: asset.title,
          status: asset.status || "draft",
          version: active_v&.version_number || 1,

          properties: merged_props,

          # Sortable metadata surfaced at the top level for the UI
          size:         merged_props["size"] || merged_props["file_size"] || 0,
          content_type: merged_props["content_type"],
          created_at:   asset.created_at,
          updated_at:   asset.updated_at,

          url: asset_url_for(asset),
        }
      end

      # Standardised folder payload (also exposes sortable timestamps).
      def format_folder_payload(folder)
        {
          id:          folder.id,
          name:        folder.name,
          slug:        folder.slug,
          description: folder.description,
          created_at:  folder.created_at,
          updated_at:  folder.updated_at,
        }
      end

      # ── Sorting helpers ─────────────────────────────────────────────────────
      ALLOWED_SORT_FIELDS = %w[name created_at updated_at size type].freeze

      def sort_field
        field = params[:sort].to_s
        ALLOWED_SORT_FIELDS.include?(field) ? field : "name"
      end

      def sort_direction
        params[:direction].to_s == "desc" ? "desc" : "asc"
      end

      # Folders only support name/created_at/updated_at sorting (no size/type).
      def sort_folders(folders)
        field = sort_field
        field = "name" if %w[size type].include?(field) # folders have no size/type

        sorted = folders.sort_by do |f|
          case field
          when "created_at" then f[:created_at] || Time.at(0)
          when "updated_at" then f[:updated_at] || Time.at(0)
          else f[:name].to_s.downcase
          end
        end

        sort_direction == "desc" ? sorted.reverse : sorted
      end

      def sort_assets(assets)
        field = sort_field

        sorted = assets.sort_by do |a|
          case field
          when "created_at" then a[:created_at] || Time.at(0)
          when "updated_at" then a[:updated_at] || Time.at(0)
          when "size"       then a[:size].to_i
          when "type"       then a[:content_type].to_s.downcase
          else a[:title].to_s.downcase
          end
        end

        sort_direction == "desc" ? sorted.reverse : sorted
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
        crumbs.unshift({ id: "root", name: "Home" })
        crumbs
      end

      def folder_params
        params.require(:folder).permit(:name, :parent_id, :description)
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
        assignment.folder_id.to_s == folder_id.to_s ? "direct" : "inherited"
      end

      def serialize_schema(schema)
        {
          id:          schema.id,
          name:        schema.name,
          slug:        schema.slug,
          level:       schema.level,
          description: schema.description,
          is_builtin:  schema.is_builtin,
          tabs:        schema.tabs || [],
        }
      end
    end
  end
end
