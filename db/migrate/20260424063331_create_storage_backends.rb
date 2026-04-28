class CreateStorageBackends < ActiveRecord::Migration[7.1]
  def change
    # Ensure this says id: :uuid
    create_table :storage_backends, id: :uuid do |t|
      t.string :name, null: false
      t.string :provider_type, null: false # s3, azure, local, etc.
      t.jsonb :configuration, default: {}, null: false
      t.boolean :active, default: true

      t.timestamps
    end
  end
end