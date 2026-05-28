module Api
  module V1
    class FoldersController < ApplicationController
      before_action :authenticate_user!

      def index
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
          @assets = Asset.active.where(folder_id: nil)

          breadcrumbs = [{ id: 'root', name: 'Home' }]
        else
          # Ensure a user cannot hack the URL to view a deleted folder
          current_folder = Folder.active.find(params[:id])

          # Filter subfolders and assets by active scope
          @folders = Folder.active.where(parent_id: current_folder.id)
          @assets = Asset.active.where(folder_id: current_folder.id)

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

      # DELETE /api/v1/folders/:id (Soft Delete)
      def destroy
        @folder = Folder.find(params[:id])
        @folder.soft_delete
        render json: { success: true, message: "Folder moved to bin" }
      end

      # POST /api/v1/folders/:id/restore
      def restore
        @folder = Folder.trashed.find(params[:id])
        @folder.restore
        render json: { success: true, message: "Folder restored" }
      end

      # DELETE /api/v1/folders/:id/permanent
      def permanent_delete
        @folder = Folder.trashed.find(params[:id])

        # Note: If deleting a folder should also permanently delete all assets inside it,
        # you need `dependent: :destroy` on your Folder model's `has_many :assets` association.
        @folder.destroy
        render json: { success: true, message: "Folder permanently deleted" }
      end

      private

      # Helper to standardize the asset payload structure for React
      def format_asset_payload(asset)
        {
          id: asset.id,
          title: asset.title,
          name: asset.title,
          status: asset.status,
          properties: asset.properties,
          # Replace with actual ActiveStorage or CDN URL generation helper
          url: asset.properties['storage_path'] ? "https://cdn.yourdam.com/assets/#{asset.uuid}" : nil
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
    end
  end
end