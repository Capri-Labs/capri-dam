class ApplySchemaToFolderJob < ApplicationJob
  queue_as :default

  # Applies a metadata schema to a folder and all its assets.
  # Optionally cascades into sub-folders.
  #
  # @param folder_id    [String]  UUID of the target folder
  # @param schema_id    [Integer] ID of the MetadataSchema to apply
  # @param cascade      [Boolean] Whether to recurse into sub-folders
  # @param initiated_by [Integer] User ID who triggered the action
  def perform(folder_id:, schema_id:, cascade: true, initiated_by: nil)
    schema = MetadataSchema.active.find_by(id: schema_id)
    return unless schema

    apply_to_folder(folder_id, schema, cascade: cascade, user_id: initiated_by)
  end

  private

  def apply_to_folder(folder_id, schema, cascade:, user_id:)
    # 1. Upsert the folder → schema assignment.
    #
    # NOTE: We must NOT use find_or_create_by!(folder_id, metadata_schema_id).
    # That compound key means "changing" the schema creates a second row (the
    # old assignment stays, find_by(folder_id:) returns the stale one, so the
    # UI never reflects the change).  We replace any existing assignment first.
    if folder_id.present? && folder_id != "root"
      ActiveRecord::Base.transaction do
        MetadataSchemaFolderAssignment.where(folder_id: folder_id).destroy_all
        MetadataSchemaFolderAssignment.create!(
          folder_id:          folder_id,
          metadata_schema_id: schema.id
        )
      end
    end

    # 2. Apply schema_id to all assets directly in this folder
    apply_to_assets(folder_id, schema, user_id: user_id)
    FolderContentsCache.bust(folder_id.presence)

    # 3. Recursively apply to child folders
    if cascade
      child_folder_ids = Folder.active.where(parent_id: folder_id).pluck(:id)
      child_folder_ids.each do |child_id|
        apply_to_folder(child_id.to_s, schema, cascade: true, user_id: user_id)
      end
    end
  end

  def apply_to_assets(folder_id, schema, user_id:)
    scope = folder_id.blank? || folder_id == "root" ? Asset.active.where(folder_id: nil) : Asset.active.where(folder_id: folder_id)

    scope.find_each do |asset|
      # Determine the most-specific schema for this asset's MIME type
      mime_type      = asset.properties&.dig("content_type").to_s
      resolved_schema = MetadataSchema.resolve_for_mime(mime_type, root_schema_id: schema.id)
      target_schema   = resolved_schema || schema

      # Merge — don't overwrite existing property values
      merged_props = asset.properties.merge(
        "applied_schema_id"   => target_schema.id,
        "applied_schema_slug" => target_schema.slug,
        "applied_schema_name" => target_schema.name
      )
      asset.update_columns(properties: merged_props, updated_at: Time.current)
    end
  end
end
