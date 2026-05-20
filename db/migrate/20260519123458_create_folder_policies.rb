class CreateFolderPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :folder_policies do |t|
      # Added `type: :uuid` here to match your Folder table's primary key
      t.references :folder, type: :uuid, null: false, foreign_key: true
      t.references :user_group, null: false, foreign_key: true

      # The Permission Matrix Capabilities
      t.boolean :read_access, default: false, null: false
      t.boolean :write_access, default: false, null: false
      t.boolean :delete_access, default: false, null: false
      t.boolean :manage_access, default: false, null: false
      t.boolean :approval_flow, default: false, null: false # Bridge to workflow queues

      t.timestamps
    end

    # Enforce database integrity: One rule configuration per group per folder
    add_index :folder_policies, [:folder_id, :user_group_id], unique: true
  end
end