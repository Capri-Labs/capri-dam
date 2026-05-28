class FixFolderIdsInWorkflows < ActiveRecord::Migration[7.0]
  def change
    # 1. Remove the broken integer columns
    remove_column :workflows, :target_folder_ids
    remove_column :workflows, :exclude_folder_ids

    # 2. Add them back as string arrays so they can hold the UUIDs
    add_column :workflows, :target_folder_ids, :string, array: true, default: []
    add_column :workflows, :exclude_folder_ids, :string, array: true, default: []
  end
end