class CreateCollections < ActiveRecord::Migration[8.1]
  def change
    create_table :collections do |t|
      t.string :name
      t.text :description
      t.string :slug
      t.uuid :uuid
      t.integer :user_id
      t.jsonb :properties
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :collections, :slug, unique: true
    add_index :collections, :uuid, unique: true
  end
end
