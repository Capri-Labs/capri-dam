module Api
  module V1
    class FoldersController < ApplicationController
      before_action :authenticate_user!

      def show
        if params[:id] == 'root'
          @folders = current_user.folders.where(parent_id: nil)
          @assets = current_user.assets.where(folder_id: nil)
          @breadcrumbs = [{ id: 'root', name: 'Home' }]
        else
          @folder = current_user.folders.find(params[:id])
          @folders = @folder.children
          @assets = @folder.assets
          @breadcrumbs = @folder.path_hierarchy
        end

        render json: {
          folders: @folders,
          assets: @assets,
          breadcrumbs: @breadcrumbs
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

      private

      def folder_params
        params.require(:folder).permit(:name, :parent_id)
      end
    end
  end
end