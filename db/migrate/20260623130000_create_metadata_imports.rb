class CreateMetadataImports < ActiveRecord::Migration[8.1]
  def change
    create_table :metadata_imports do |t|
      t.string  :name, null: false
      t.integer :status, default: 0, null: false

      # Ownership
      t.bigint  :user_id, null: false

      # Import settings
      t.integer :batch_size, default: 50, null: false
      t.string  :field_separator, default: ",", null: false
      t.string  :multi_value_delimiter, default: "|", null: false
      t.boolean :launch_workflows, default: false, null: false
      t.string  :asset_path_column, default: "asset_path", null: false
      t.jsonb   :ignored_columns, default: [], null: false

      # Scheduling
      t.datetime :scheduled_at

      # Results / bookkeeping
      t.integer  :total_rows,     default: 0, null: false
      t.integer  :success_count,  default: 0, null: false
      t.integer  :failure_count,  default: 0, null: false
      t.text     :error_message
      t.datetime :expires_at

      t.timestamps
    end

    add_index :metadata_imports, :user_id
    add_index :metadata_imports, :status
    add_index :metadata_imports, :expires_at

    add_foreign_key :metadata_imports, :users
  end
end

