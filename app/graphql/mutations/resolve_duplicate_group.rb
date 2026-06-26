# frozen_string_literal: true

module Mutations
  # GraphQL mutation to resolve a {DuplicateGroup}.
  #
  # == Inputs
  #
  # * +group_id+            — UUID of the duplicate group to resolve
  # * +action+              — +"kept_all"+ | +"deleted_duplicates"+
  # * +asset_ids_to_delete+ — Array of asset UUIDs to soft-delete
  #                           (only meaningful when action == "deleted_duplicates")
  #
  # == Returns
  #
  # * +group+   — the updated {Types::DuplicateGroupType}
  # * +errors+  — validation error messages
  #
  # @see DuplicateGroup#resolve!
  class ResolveDuplicateGroup < Mutations::BaseMutation
    description "Resolve a duplicate group by keeping all assets or deleting chosen copies."

    argument :group_id,             String,   required: true,
             description: "UUID of the duplicate group to resolve."
    argument :action,               String,   required: true,
             description: "'kept_all' or 'deleted_duplicates'."
    argument :asset_ids_to_delete,  [ String ], required: false, default_value: [],
             description: "Asset UUIDs to soft-delete (ignored for kept_all)."

    field :group,   Types::DuplicateGroupType, null: true
    field :errors,  [ String ],                  null: false

    def resolve(group_id:, action:, asset_ids_to_delete: [])
      unless context[:current_user]
        return { group: nil, errors: [ "Authentication required." ] }
      end

      unless %w[kept_all deleted_duplicates].include?(action)
        return { group: nil, errors: [ "Invalid action. Use kept_all or deleted_duplicates." ] }
      end

      dup_group = DuplicateGroup.find_by(id: group_id)
      return { group: nil, errors: [ "Duplicate group not found." ] } unless dup_group

      soft_deleted = []

      if action == "deleted_duplicates" && asset_ids_to_delete.any?
        original_id = dup_group.duplicate_group_assets
                                .where(is_original: true)
                                .pick(:asset_id)

        asset_ids_to_delete.each do |uid|
          next if uid.to_s == original_id.to_s
          asset = Asset.find_by(id: uid)
          next unless asset

          asset.update!(deleted_at: Time.current)
          soft_deleted << uid
        end
      end

      dup_group.resolve!(action: action, user: context[:current_user])
      { group: dup_group.reload, errors: [] }
    rescue ActiveRecord::RecordNotFound => e
      { group: nil, errors: [ e.message ] }
    rescue StandardError => e
      { group: nil, errors: [ e.message ] }
    end
  end
end
