class AddFolderRulesToWorkflows < ActiveRecord::Migration[7.0]
  def change
    add_column :workflows, :folder_scope, :string, default: 'all'
    add_column :workflows, :target_folder_ids, :uuid, array: true, default: []
    add_column :workflows, :exclude_folder_ids, :uuid, array: true, default: []
  end
end