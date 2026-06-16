class CreateAssetVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :asset_versions, id: :uuid do |t|
      t.references :asset, null: false, foreign_key: true, type: :uuid
      t.integer :version_number, null: false, default: 1
      t.string :action_type, default: 'initial_upload' # e.g., 'initial_upload', 'cropped', 'background_removed'
      t.jsonb :properties, default: {} # Stores physical specs of this specific version

      # Assuming you have a users table for audit trails
      t.references :created_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    # Add the active pointer to the main assets table
    add_reference :assets, :active_version, foreign_key: { to_table: :asset_versions }, type: :uuid

    # Ensure version numbers are unique per asset
    add_index :asset_versions, [:asset_id, :version_number], unique: true
  end
end