# Aligns FolderPolicy permission columns with the DAM ACL vocabulary:
#
# * Renames +write_access+  → +modify_access+   (modify existing content)
# * Adds    +create_access+                      (upload assets / create folders)
# * Renames +approval_flow+ → +replicate_access+ (push to CDN)
# * Retains +manage_access+ for future super-admin gating.
class UpdateFolderPoliciesAcl < ActiveRecord::Migration[8.1]
  def up
    rename_column :folder_policies, :write_access,   :modify_access
    rename_column :folder_policies, :approval_flow,  :replicate_access

    add_column :folder_policies, :create_access, :boolean, default: false, null: false
  end

  def down
    remove_column :folder_policies, :create_access

    rename_column :folder_policies, :replicate_access, :approval_flow
    rename_column :folder_policies, :modify_access,    :write_access
  end
end

