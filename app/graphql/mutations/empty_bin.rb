# frozen_string_literal: true

module Mutations
  # Permanently empties the entire Recycle Bin (admin only).
  #
  # All trashed assets (including all versions and physical files) and folders
  # are irreversibly destroyed.  This action is audited.
  #
  # == Returns
  # * +deleted+ — total number of records permanently removed
  # * +errors+  — any failure messages
  class EmptyBin < Mutations::BaseMutation
    description "Permanently delete all items in the Recycle Bin (admin only)."

    field :deleted, Integer,    null: true
    field :errors,  [ String ], null: false

    def resolve
      user = context[:current_user]
      return { deleted: nil, errors: [ "Authentication required." ] } unless user
      return { deleted: nil, errors: [ "Administrator privileges required." ] } unless user.admin?

      deleted = 0

      Folder.trashed.find_each { |f| f.destroy && (deleted += 1) }

      backend = ::StorageBackend.find_by(active: true)
      storage = ::StorageManager.adapter_for(backend) if backend

      Asset.trashed.includes(:asset_versions).find_each do |asset|
        asset.asset_versions.each do |version|
          storage_path = version.properties["storage_path"]
          storage&.delete(storage_path) if storage_path
          version.file.purge if version.respond_to?(:file) && version.file.attached?
        end
        # Without this, destroying an asset that was ever flagged by duplicate
        # detection raises ActiveRecord::InvalidForeignKey on duplicate_group_assets.
        ::DuplicateGroupAsset.cleanup_for_asset!(asset, log_prefix: "[EmptyBin]")
        asset.update_column(:active_version_id, nil) if asset.active_version_id # rubocop:disable Rails/SkipsModelValidations
        asset.destroy
        deleted += 1
      end

      { deleted: deleted, errors: [] }
    rescue StandardError => e
      { deleted: nil, errors: [ e.message ] }
    end
  end
end
