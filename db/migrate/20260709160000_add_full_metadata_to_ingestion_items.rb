class AddFullMetadataToIngestionItems < ActiveRecord::Migration[8.1]
  def change
    # Raw, un-normalized payload returned by the source system's per-asset
    # metadata endpoint (e.g. AEM's jcr:content/metadata.json), captured only
    # when IngestionBatch#migrate_metadata is enabled. Kept separate from
    # legacy_metadata (which already holds the merged/canonical selective +
    # full metadata used by the AI transform step) so the Batch Review audit
    # view can show operators exactly what was fetched from the source system,
    # independent of how it was subsequently normalized.
    add_column :ingestion_items, :full_metadata, :jsonb, default: {}, null: false
  end
end
