class CreateIngestionItems < ActiveRecord::Migration[8.1]
  def change
    create_table :ingestion_items, id: :uuid do |t|
      # Explicitly use UUID for the foreign key
      t.references :ingestion_batch, type: :uuid, null: false, foreign_key: true

      t.string :original_filename, null: false
      t.string :file_hash # SHA-256 for cryptographic deduplication
      t.integer :file_size, limit: 8 # Tracking bytes to calculate TDM storage savings

      t.integer :status, default: 0, null: false

      t.jsonb :legacy_metadata, default: {} # The messy raw data dump
      t.jsonb :clean_properties, default: {} # The transformed data after AI processing
      t.text :error_log # For conflict resolution

      t.timestamps
    end

    # Crucial index for the deduplication engine
    add_index :ingestion_items, :file_hash
  end
end