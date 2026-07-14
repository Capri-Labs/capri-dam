module Api
  module V1
    # Bulk "Copy" endpoint backing the Explorer Tools-menu Copy overlay.
    #
    # Copying duplicates the selected folders/assets (recursing into any
    # subfolders/assets for a folder selection) into a destination folder,
    # leaving every original untouched. Because nothing is removed from the
    # source, only two permission checks apply — one fewer than Move:
    #
    #   * +:read+ on the item's *current* parent folder (you must be able to
    #     view the content you're duplicating)
    #   * +:create+ on the *destination* folder (you must be allowed to add
    #     content there)
    #
    # A +nil+/"root" folder always passes both checks (no {FolderPolicy} can
    # apply at the root). Admins bypass all checks, matching the rest of the
    # authorization model.
    #
    # Name collisions in the destination are resolved automatically by
    # appending " (Copy)", " (Copy 2)", etc. — mirroring familiar OS file
    # manager behaviour — rather than failing the item outright. Copies are
    # always owned by the requesting user, matching the fact that they are
    # newly *created* content (gated by the destination's +:create+ check).
    #
    # Each folder/asset is evaluated independently so a single item failing
    # permission or validation does not abort the rest of the batch — the
    # response reports per-item errors alongside the overall success counts.
    class CopyOperationsController < ApplicationController
      include AssetUrlHelper

      before_action :authenticate_hybrid!
      before_action :require_write_scope!

      # POST /api/v1/copy_operations
      #   { folder_ids: [1, 2], asset_ids: [10], destination_folder_id: 5 }
      #   destination_folder_id may be nil / "root" to copy to the top level.
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
        copied_folders = 0
        copied_assets  = 0

        folder_ids.each do |folder_id|
          folder = Folder.active.find_by(id: folder_id)
          if folder.nil?
            errors << { type: "folder", id: folder_id, error: "Folder not found." }
            next
          end

          if folder.self_or_ancestor_match?(destination_id)
            errors << { type: "folder", id: folder.id, name: folder.name,
                         error: "Cannot copy a folder into itself or one of its own subfolders." }
            next
          end

          unless folder_permission?(folder.parent, :read) && folder_permission?(destination_folder, :create)
            errors << { type: "folder", id: folder.id, name: folder.name,
                         error: "You do not have permission to copy this folder." }
            next
          end

          begin
            duplicate_folder_tree(folder, destination_id)
            touched_folder_ids << destination_id
            copied_folders += 1
          rescue ActiveRecord::RecordInvalid => e
            errors << { type: "folder", id: folder.id, name: folder.name,
                         error: e.record.errors.full_messages.to_sentence }
          end
        end

        asset_ids.each do |asset_id|
          asset = Asset.active.find_by(id: asset_id)
          if asset.nil?
            errors << { type: "asset", id: asset_id, error: "Asset not found." }
            next
          end

          source_folder = asset.folder_id ? Folder.find_by(id: asset.folder_id) : nil
          unless folder_permission?(source_folder, :read) && folder_permission?(destination_folder, :create)
            errors << { type: "asset", id: asset.id, name: asset.title,
                         error: "You do not have permission to copy this asset." }
            next
          end

          begin
            duplicate_asset(asset, destination_id)
            touched_folder_ids << destination_id
            copied_assets += 1
          rescue ActiveRecord::RecordInvalid => e
            errors << { type: "asset", id: asset.id, name: asset.title,
                         error: e.record.errors.full_messages.to_sentence }
          end
        end

        touched_folder_ids.each { |fid| FolderContentsCache.bust(fid) }

        status = errors.any? && copied_folders.zero? && copied_assets.zero? ? :unprocessable_entity : :ok
        render json: {
          success: errors.empty?,
          copied_folders: copied_folders,
          copied_assets: copied_assets,
          errors: errors,
        }, status: status
      end

      private

      # Recursively duplicates +folder+ — including every active descendant
      # folder and asset — as a new subtree rooted under +destination_id+.
      #
      # @param folder [Folder] source subtree root
      # @param destination_id [String, Integer, nil] parent id for the new copy
      # @return [Folder] the newly created top-level copy
      def duplicate_folder_tree(folder, destination_id)
        new_folder = Folder.new(
          name: unique_folder_name(folder.name, destination_id),
          description: folder.description,
          properties: folder.properties,
          parent_id: destination_id,
          user: current_user,
        )
        new_folder.save!

        folder.children.active.each { |child| duplicate_folder_tree(child, new_folder.id) }
        folder.assets.active.each { |asset| duplicate_asset(asset, new_folder.id) }

        new_folder
      end

      # Duplicates +asset+ — its metadata plus the active version's stored
      # file — into +destination_id+.
      #
      # @param asset [Asset] source asset
      # @param destination_id [String, Integer, nil] destination folder id
      # @return [Asset] the newly created copy
      def duplicate_asset(asset, destination_id)
        new_asset = Asset.new(
          title: unique_asset_title(asset.title, destination_id),
          properties: asset.properties,
          status: asset.status,
          folder_id: destination_id,
          user: current_user,
          uuid: SecureRandom.uuid,
        )
        new_asset.save!

        source_version = asset.active_version
        if source_version
          new_version = new_asset.asset_versions.new(
            version_number: 1,
            action_type: "copy",
            properties: source_version.properties,
            created_by: current_user,
          )
          copy_version_file(source_version, new_version, new_asset)
          new_version.save!
          new_asset.update!(active_version_id: new_version.id)
        end

        new_asset
      end

      # Duplicates the physical file backing +source_version+ onto a new
      # path for +new_version+/+new_asset+, using whichever storage
      # provider is currently active (local disk, S3, GCS, ...).
      #
      # +storage_path+ — not the legacy ActiveStorage attachment — is the
      # authoritative location of an asset's file (see
      # Api::V1::AssetsController and AssetProcessorWorker, which write it
      # right after upload/processing and use it to serve every request).
      # ActiveStorage attachments are unreliable for these uuid-keyed
      # models: active_storage_attachments.record_id is a bigint column,
      # so every attachment's record_id is coerced to 0 and `attached?`
      # can return true for a *different* record's blob. Copying via
      # +storage_path+ avoids that pitfall entirely and matches how the
      # rest of the app treats "the file" as source of truth.
      #
      # Falls back to sharing the legacy ActiveStorage blob only when the
      # source version has no +storage_path+ (e.g. old/seed data) but does
      # have a real attachment.
      def copy_version_file(source_version, new_version, new_asset)
        storage_path = source_version.properties["storage_path"]

        if storage_path.present?
          ext = File.extname(storage_path)
          dest_path = "#{new_asset.uuid}/v1_#{SecureRandom.hex(4)}#{ext}"
          StorageManager.active_adapter.copy(storage_path, dest_path)
          new_version.properties = new_version.properties.merge("storage_path" => dest_path)
        elsif source_version.file&.attached?
          new_version.file.attach(source_version.file.blob)
        end
      end

      # Keeps the source name when there's no collision in the destination
      # (copying elsewhere shouldn't rename anything); otherwise appends
      # " (Copy)", " (Copy 2)", … until unique — mirroring familiar OS file
      # manager behaviour for same-folder duplication.
      def unique_folder_name(base_name, destination_id)
        return base_name unless Folder.active.exists?(name: base_name, parent_id: destination_id, user_id: current_user.id)

        candidate = "#{base_name} (Copy)"
        n = 2
        while Folder.active.exists?(name: candidate, parent_id: destination_id, user_id: current_user.id)
          candidate = "#{base_name} (Copy #{n})"
          n += 1
        end
        candidate
      end

      # Asset titles carry no uniqueness constraint, but avoiding an exact
      # duplicate title within the same destination folder keeps copies
      # visually distinguishable from their source.
      def unique_asset_title(base_name, destination_id)
        return base_name unless Asset.active.exists?(title: base_name, folder_id: destination_id)

        candidate = "#{base_name} (Copy)"
        n = 2
        while Asset.active.exists?(title: candidate, folder_id: destination_id)
          candidate = "#{base_name} (Copy #{n})"
          n += 1
        end
        candidate
      end
    end
  end
end
