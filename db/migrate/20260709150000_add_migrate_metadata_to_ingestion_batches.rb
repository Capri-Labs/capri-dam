class AddMigrateMetadataToIngestionBatches < ActiveRecord::Migration[8.1]
  def change
    # Controls whether the extraction pipeline performs an additional, full
    # per-asset metadata fetch (e.g. AEM's `jcr:content/metadata.json` node)
    # instead of relying solely on the lightweight "selective" properties
    # pulled alongside the file listing. Defaults to enabled per product
    # requirement — most migrations want complete metadata by default, and
    # can opt out via the migration wizard for faster, listing-only imports.
    add_column :ingestion_batches, :migrate_metadata, :boolean, default: true, null: false
  end
end
