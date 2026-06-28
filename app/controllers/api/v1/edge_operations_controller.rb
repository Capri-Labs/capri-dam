module Api
  module V1
    class EdgeOperationsController < ApplicationController
      before_action :authenticate_hybrid!

      # POST /api/v1/edge_operations/sync
      def sync
        folders = params.fetch(:folders, [])
        assets = params.fetch(:assets, [])

        # 1. Dispatch Folder Fan-Out Workers
        folders.each do |folder_id|
          FolderMetadataSyncWorker.perform_async(folder_id)
        end

        # 2. Dispatch Direct Asset Workers
        assets.each do |asset_uuid|
          EdgeMetadataSyncWorker.perform_async(asset_uuid)
        end

        render json: {
          success: true,
          message: "Metadata sync initiated for #{folders.size} folders and #{assets.size} assets.",
        }, status: :accepted
      end

      # POST /api/v1/edge_operations/purge
      def purge
        folders = params.fetch(:folders, [])
        assets = params.fetch(:assets, [])

        # 1. Dispatch Folder Purge Workers
        # (This invalidates the folder's cache tag at the edge)
        folders.each do |folder_id|
          CdnInvalidationWorker.perform_async("folder", folder_id)
        end

        # 2. Dispatch Asset Purge Workers
        # (This invalidates the specific asset's cache tag)
        assets.each do |asset_uuid|
          CdnInvalidationWorker.perform_async("asset", asset_uuid)
        end

        render json: {
          success: true,
          message: "Cache purge initiated for #{folders.size} folders and #{assets.size} assets.",
        }, status: :accepted
      end
    end
  end
end
