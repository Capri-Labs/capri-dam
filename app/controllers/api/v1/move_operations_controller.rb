module Api
  module V1
    # Bulk "Move" endpoint backing the Explorer Tools-menu Move overlay.
    #
    # Moving is modelled as removing an item from its current folder and
    # adding it to a destination folder, so it is gated by two permission
    # checks rather than one:
    #
    #   * +:delete+ on the item's *current* parent folder (you must be
    #     allowed to remove content from where it lives today)
    #   * +:create+ on the *destination* folder (you must be allowed to add
    #     content there)
    #
    # A +nil+/"root" folder always passes both checks (no {FolderPolicy} can
    # apply at the root). Admins bypass all checks, matching the rest of the
    # authorization model.
    #
    # Each folder/asset is evaluated independently so a single item failing
    # permission or validation (e.g. name collision, cyclical move) does not
    # abort the rest of the batch — the response reports per-item errors
    # alongside the overall success counts.
    class MoveOperationsController < ApplicationController
      include AssetUrlHelper

      before_action :authenticate_hybrid!
      before_action :require_write_scope!

      # POST /api/v1/move_operations
      #   { folder_ids: [1, 2], asset_ids: [10], destination_folder_id: 5 }
      #   destination_folder_id may be nil / "root" to move to the top level.
      def create
        folder_ids = Array(params[:folder_ids]).reject(&:blank?)
        asset_ids  = Array(params[:asset_ids]).reject(&:blank?)

        if folder_ids.empty? && asset_ids.empty?
          return render json: { error: "No folders or assets were specified." }, status: :unprocessable_entity
        end

        destination_id = params[:destination_folder_id]
        destination_id = nil if destination_id.blank? || destination_id == "root"
        destination_folder = destination_id.present? ? Folder.active.find_by(id: destination_id) : nil

        if destination_id.present? && destination_folder.nil?
          return render json: { error: "Destination folder not found." }, status: :not_found
        end

        errors = []
        touched_folder_ids = Set.new([ destination_id ])
        moved_folders = 0
        moved_assets  = 0

        folder_ids.each do |folder_id|
          folder = Folder.active.find_by(id: folder_id)
          if folder.nil?
            errors << { type: "folder", id: folder_id, error: "Folder not found." }
            next
          end

          if folder.self_or_ancestor_match?(destination_id)
            errors << { type: "folder", id: folder.id, name: folder.name,
                         error: "Cannot move a folder into itself or one of its own subfolders." }
            next
          end

          unless folder_permission?(folder.parent, :delete) && folder_permission?(destination_folder, :create)
            errors << { type: "folder", id: folder.id, name: folder.name,
                         error: "You do not have permission to move this folder." }
            next
          end

          old_parent_id = folder.parent_id
          if folder.update(parent_id: destination_id)
            touched_folder_ids << old_parent_id
            touched_folder_ids << destination_id
            moved_folders += 1
          else
            errors << { type: "folder", id: folder.id, name: folder.name,
                         error: folder.errors.full_messages.to_sentence }
          end
        end

        asset_ids.each do |asset_id|
          asset = Asset.active.find_by(id: asset_id)
          if asset.nil?
            errors << { type: "asset", id: asset_id, error: "Asset not found." }
            next
          end

          source_folder = asset.folder_id ? Folder.find_by(id: asset.folder_id) : nil
          unless folder_permission?(source_folder, :delete) && folder_permission?(destination_folder, :create)
            errors << { type: "asset", id: asset.id, name: asset.title,
                         error: "You do not have permission to move this asset." }
            next
          end

          old_folder_id = asset.folder_id
          if asset.update(folder_id: destination_id)
            touched_folder_ids << old_folder_id
            touched_folder_ids << destination_id
            moved_assets += 1
          else
            errors << { type: "asset", id: asset.id, name: asset.title,
                         error: asset.errors.full_messages.to_sentence }
          end
        end

        touched_folder_ids.each { |fid| FolderContentsCache.bust(fid) }

        status = errors.any? && moved_folders.zero? && moved_assets.zero? ? :unprocessable_entity : :ok
        render json: {
          success: errors.empty?,
          moved_folders: moved_folders,
          moved_assets: moved_assets,
          errors: errors,
        }, status: status
      end
    end
  end
end
