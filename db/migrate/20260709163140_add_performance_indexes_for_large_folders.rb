class AddPerformanceIndexesForLargeFolders < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Speeds up the two hottest queries behind FoldersController#show:
  #   Asset.active.where(folder_id: X)   == WHERE folder_id = X AND deleted_at IS NULL
  #   Folder.active.where(parent_id: X)  == WHERE parent_id = X AND deleted_at IS NULL
  #
  # Both columns already have separate btree indexes (index_assets_on_folder_id,
  # index_assets_on_deleted_at, index_folders_on_parent_id,
  # index_folders_on_deleted_at), so Postgres *can* satisfy these queries today
  # via a BitmapAnd of the two single-column indexes — but a single composite
  # index lets the planner do it in one index scan instead, which matters once
  # a folder holds 1,000-3,000+ assets.
  def change
    add_index :assets, [ :folder_id, :deleted_at ],
      name: "index_assets_on_folder_id_and_deleted_at",
      algorithm: :concurrently

    add_index :folders, [ :parent_id, :deleted_at ],
      name: "index_folders_on_parent_id_and_deleted_at",
      algorithm: :concurrently

    # Targeted expression (functional) indexes for the handful of JSONB
    # `properties` keys that are queried via `properties->>'key'` equality/
    # ILIKE/cast comparisons in Api::V1::SearchController (mime_group,
    # file_size_group, schema_id, orientation/style filters, editable checks,
    # etc). The existing GIN index on the whole `properties` column
    # (index_assets_on_properties) only accelerates containment operators
    # (`@>`, `?`, `?&`, `?|`) — it does NOT speed up `->>'key'` extraction,
    # which is what all of these fixed, hardcoded filters actually use.
    #
    # NOTE: with 100+ possible metadata schema fields, we deliberately do NOT
    # try to index every key — most of those are arbitrary, per-schema custom
    # fields queried dynamically (see
    # Api::V1::SearchController#apply_dynamic_filters) and a static per-key
    # index can't cover all of them. Only the keys with fixed, hardcoded query
    # call sites (i.e. ones we know are hot *today*, not hypothetically) get a
    # dedicated index below. If a specific custom field becomes a hot filter
    # path in the future, add a matching expression index for it the same way.
    add_index :assets, "((properties->>'content_type'))",
      name: "index_assets_on_properties_content_type",
      algorithm: :concurrently

    add_index :assets, "((properties->>'applied_schema_id'))",
      name: "index_assets_on_properties_applied_schema_id",
      algorithm: :concurrently

    # `file_size` is normally numeric, but arbitrary/legacy data can contain a
    # blank or non-numeric string (see spec/requests/api/v1/data_health_spec.rb,
    # which deliberately seeds `"file_size" => ""` to exercise a data-quality
    # dashboard). Expression indexes evaluate on every INSERT/UPDATE, so an
    # unconditional `::bigint` cast would raise
    # PG::InvalidTextRepresentation the moment such a row is written. Scoping
    # the index to only numeric-looking values (partial index) avoids that
    # while still indexing the vast majority of real, well-formed rows.
    add_index :assets, "(((properties->>'file_size')::bigint))",
      name: "index_assets_on_properties_file_size",
      where: "(properties->>'file_size') ~ '^[0-9]+$'",
      algorithm: :concurrently
  end
end
