class AddExplicitDenyToFolderPolicies < ActiveRecord::Migration[8.1]
  def change
    add_column :folder_policies, :explicit_deny, :boolean, default: false, null: false
  end
end