class CreateRenditions < ActiveRecord::Migration[7.1]
  def change
    create_table :renditions, id: :uuid do |t|
      # Reference UUIDs for both
      t.references :asset, type: :uuid, foreign_key: true, null: false
      t.references :storage_backend, type: :uuid, foreign_key: true, null: false

      t.string :storage_key, null: false
      t.string :kind, null: false # 'original', 'thumb', etc.
      t.integer :width
      t.integer :height
      t.bigint :file_size
      t.string :content_type
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end
  end
end