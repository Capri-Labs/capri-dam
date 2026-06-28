# frozen_string_literal: true

# Propagates an access-policy change (upsert or remove) to all child folders
# of a given folder, recursing the full subtree.
#
# Enqueued by {Api::V1::FoldersController#upsert_folder_policy} and
# {Api::V1::FoldersController#remove_folder_policy} when the caller requests
# cascade behaviour.
#
# @example Cascade an upsert
#   PropagateAccessPolicyJob.perform_later(
#     folder_id:   folder.id,
#     group_id:    group.id,
#     permissions: { read_access: true, modify_access: false, ... },
#     operation:   "upsert"
#   )
#
# @example Cascade a removal
#   PropagateAccessPolicyJob.perform_later(
#     folder_id: folder.id,
#     group_id:  group.id,
#     permissions: {},
#     operation:  "remove"
#   )
class PropagateAccessPolicyJob < ApplicationJob
  queue_as :default

  # @param folder_id   [String, Integer]  UUID of the *parent* folder whose children will be updated
  # @param group_id    [Integer]          UserGroup ID
  # @param permissions [Hash]             Permission columns to set (only used for :upsert)
  # @param operation   [String]           "upsert" | "remove"
  def perform(folder_id:, group_id:, permissions:, operation:)
    recurse(folder_id, group_id, permissions.symbolize_keys, operation)
  end

  private

  PERMISSION_KEYS = %i[
    read_access modify_access create_access
    delete_access replicate_access manage_access explicit_deny
  ].freeze

  def recurse(folder_id, group_id, permissions, operation)
    Folder.active.where(parent_id: folder_id).find_each do |child|
      case operation
      when "upsert"
        safe_perms = permissions.slice(*PERMISSION_KEYS)
        policy = FolderPolicy.find_or_initialize_by(
          folder_id:    child.id,
          user_group_id: group_id
        )
        policy.assign_attributes(safe_perms)
        policy.save!
      when "remove"
        FolderPolicy.where(folder_id: child.id, user_group_id: group_id).destroy_all
      end

      # Recurse into grandchildren
      recurse(child.id, group_id, permissions, operation)
    end
  end
end
