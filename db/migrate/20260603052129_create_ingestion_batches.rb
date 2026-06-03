class CreateIngestionBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :ingestion_batches, id: :uuid do |t|
      t.string :name, null: false
      t.string :source_type, null: false # e.g., 'legacy_s3', 'ftp', 'manual_zip'
      t.integer :status, default: 0, null: false
      t.integer :total_count, default: 0
      t.integer :processed_count, default: 0
      t.integer :user_id # The administrator who initiated the batch

      t.timestamps
    end
  end
end