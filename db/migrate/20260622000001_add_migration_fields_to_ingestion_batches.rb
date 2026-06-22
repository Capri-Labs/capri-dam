class AddMigrationFieldsToIngestionBatches < ActiveRecord::Migration[8.1]
  def change
    # Link batches to their source connector
    add_column :ingestion_batches, :connector_id, :bigint
    add_index  :ingestion_batches, :connector_id

    # Store source credentials inline (encrypted via ActiveRecord Encryption if desired)
    add_column :ingestion_batches, :source_credentials, :jsonb, default: {}

    # Track pipeline timing
    add_column :ingestion_batches, :completed_at, :datetime
    add_column :ingestion_batches, :started_at,   :datetime

    # Link to generated report snapshot
    add_column :ingestion_batches, :report_snapshot_id, :bigint

    # Summary counters
    add_column :ingestion_batches, :duplicate_count, :integer, default: 0
    add_column :ingestion_batches, :error_count,     :integer, default: 0
    add_column :ingestion_batches, :committed_count, :integer, default: 0

    # Who triggered the migration
    add_column :ingestion_batches, :initiated_by_id, :bigint

    # Human-readable note / migration plan description
    add_column :ingestion_batches, :notes, :text

    add_foreign_key :ingestion_batches, :system_connectors, column: :connector_id, on_delete: :nullify
  end
end

