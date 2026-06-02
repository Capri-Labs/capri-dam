class CreateCollectionAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :collection_assets do |t|
      # Assuming Collection uses the default bigint primary key
      t.references :collection, null: false, foreign_key: true

      # THE FIX: Explicitly cast the foreign key as a UUID to match the Asset table
      t.references :asset, type: :uuid, null: false, foreign_key: true

      t.integer :position, default: 0
      t.integer :user_id

      t.timestamps
    end

    # Enforce database-level uniqueness
    add_index :collection_assets, [:collection_id, :asset_id], unique: true
  end
end