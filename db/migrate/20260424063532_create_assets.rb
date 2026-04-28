class CreateAssets < ActiveRecord::Migration[7.1]
  def change
    create_table :assets, id: :uuid do |t|
      t.string :title, null: false

      # UUID: Because folders.id is a UUID
      t.references :folder, type: :uuid, foreign_key: true, null: true

      # BIGINT: Because users.id is a bigint (standard)
      t.references :user, foreign_key: true, null: false

      t.string :status, default: 'draft'
      t.string :uuid, null: false # Public identifier
      t.jsonb :properties, default: {}, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :assets, :uuid, unique: true
    add_index :assets, :properties, using: :gin
    add_index :assets, :deleted_at
  end
end