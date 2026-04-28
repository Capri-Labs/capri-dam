class CreateFolders < ActiveRecord::Migration[7.1]
  def change
    # Ensure UUID extension is enabled if this is your first migration
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')

    create_table :folders, id: :uuid do |t|
      t.string :name, null: false

      # FIXED: Points to 'folders' table instead of 'parents'
      t.references :parent,
                   type: :uuid,
                   foreign_key: { to_table: :folders },
                   null: true

      t.string :path
      t.string :slug
      t.timestamps
    end

    add_index :folders, :path
    add_index :folders, :slug
  end
end