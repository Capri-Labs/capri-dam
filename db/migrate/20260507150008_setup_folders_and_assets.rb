class SetupFoldersAndAssets < ActiveRecord::Migration[7.1]
  def change
    # 1. Folders: Add the user relationship and slug
    # (Checking exists just in case you don't db:reset)
    unless column_exists?(:folders, :user_id)
      add_reference :folders, :user, null: false, foreign_key: true
    end

    unless column_exists?(:folders, :slug)
      add_column :folders, :slug, :string
      add_index :folders, :slug
    end

    # 2. Assets: Create the table from scratch
    unless table_exists?(:assets)
      create_table :assets do |t|
        t.string :name, null: false
        t.references :user, null: false, foreign_key: true
        t.references :folder, foreign_key: true # Optional: can be at root
        t.string :file_type
        t.jsonb :metadata, default: {}
        t.timestamps
      end
    end
  end
end