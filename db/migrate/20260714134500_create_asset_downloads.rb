class CreateAssetDownloads < ActiveRecord::Migration[8.1]
  def change
    create_table :asset_downloads do |t|
      t.string  :name, null: false
      t.integer :status, default: 0, null: false

      # Selection — the folders/assets the user asked to bundle. Folders are
      # expanded recursively by the worker at run time (not persisted flat)
      # so the request payload stays small.
      t.jsonb :folder_ids, default: [], null: false
      t.jsonb :asset_ids,  default: [], null: false

      # Progress (drives the Explorer's polling progress bar)
      t.integer :total_items,     default: 0, null: false
      t.integer :processed_items, default: 0, null: false
      t.integer :file_count,      default: 0, null: false
      t.bigint  :byte_size,       default: 0, null: false

      # Ownership
      t.bigint :user_id, null: false

      t.text     :error_message
      t.datetime :expires_at

      t.timestamps
    end

    add_index :asset_downloads, :user_id
    add_index :asset_downloads, :status
    add_index :asset_downloads, :expires_at

    add_foreign_key :asset_downloads, :users
  end
end
