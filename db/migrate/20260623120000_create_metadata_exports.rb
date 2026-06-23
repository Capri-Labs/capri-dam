class CreateMetadataExports < ActiveRecord::Migration[8.1]
  def change
    create_table :metadata_exports do |t|
      t.string  :name, null: false
      t.integer :status, default: 0, null: false

      # Source scope
      t.uuid    :folder_id
      t.boolean :include_subfolders, default: false, null: false

      # Property selection: "all" or "selective"
      t.string  :property_mode, default: "all", null: false
      t.jsonb   :selected_properties, default: [], null: false

      # Ownership
      t.bigint  :user_id, null: false

      # Bookkeeping / results
      t.integer  :total_assets, default: 0, null: false
      t.integer  :file_count,   default: 0, null: false
      t.text     :error_message
      t.datetime :scheduled_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :metadata_exports, :user_id
    add_index :metadata_exports, :folder_id
    add_index :metadata_exports, :status
    add_index :metadata_exports, :expires_at

    add_foreign_key :metadata_exports, :users
  end
end

