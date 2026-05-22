class StandardizeFoldersToMatchAssets < ActiveRecord::Migration[7.1]
  def change
    # 1. Add the missing soft-delete column
    add_column :folders, :deleted_at, :datetime

    # 2. Add JSONB for custom folder metadata (colors, inherited tags, etc.)
    add_column :folders, :properties, :jsonb, default: {}

    # 3. Add UUID for secure headless sharing
    # Using Postgres' native UUID generation
    add_column :folders, :uuid, :uuid, default: -> { "gen_random_uuid()" }, null: false

    # 4. Add Indexes for performance
    # Since the API will query `Folder.trashed` or `Folder.active` constantly, an index is critical here
    add_index :folders, :deleted_at
    add_index :folders, :uuid, unique: true
  end
end