class AddTrigramSearchIndexesForLexicalSearch < ActiveRecord::Migration[8.1]
  # These indexes accelerate the ILIKE-based lexical search queries used by
  # `Api::V1::SearchController` (title/filename/full-metadata substring
  # matching, and content-type/mime prefix filters). Before this migration,
  # those queries fell back to a sequential scan on every request (see ADR-3,
  # docs/architecture/src/*[section-design-decisions]) — fine at small
  # catalog sizes, but linear with asset count.
  #
  # `pg_trgm` + a GIN index built with `gin_trgm_ops` lets Postgres use an
  # index scan for `ILIKE '%term%'` (substring), `ILIKE 'term%'` (prefix),
  # and `ILIKE '%term'` (suffix) patterns alike — unlike a plain B-tree
  # index, which only helps prefix matches. This preserves the exact
  # existing substring-match search semantics (no behavior change), it just
  # makes it index-backed.
  #
  # A plain `jsonb_ops` GIN index already exists on `assets.properties`
  # (`index_assets_on_properties`) but that only accelerates containment
  # (`@>`) / key-existence (`?`) operators — it does NOT help `->>` text
  # extraction combined with ILIKE, which is what the search controller
  # actually runs. Hence the additional expression indexes below.
  def up
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    # `title ILIKE '%...%'` — used by the main keyword search and suggestions.
    execute <<~SQL
      CREATE INDEX index_assets_on_title_trgm
        ON assets USING gin (title gin_trgm_ops);
    SQL

    # `properties->>'original_filename' ILIKE '%...%'` — used by the main
    # keyword search and suggestions.
    execute <<~SQL
      CREATE INDEX index_assets_on_properties_original_filename_trgm
        ON assets USING gin ((properties ->> 'original_filename') gin_trgm_ops);
    SQL

    # `properties::text ILIKE '%...%'` — the "search anywhere in metadata"
    # fallback used by the main keyword search and suggestions; this was the
    # most expensive of the three (a full JSONB→text cast per row on every
    # query), so it benefits the most from being index-backed.
    execute <<~SQL
      CREATE INDEX index_assets_on_properties_text_trgm
        ON assets USING gin ((properties::text) gin_trgm_ops);
    SQL

    # `properties->>'content_type' ILIKE 'image/%'` (and similar prefix
    # patterns) — used by `apply_mode_filter`/`apply_mime_group`.
    execute <<~SQL
      CREATE INDEX index_assets_on_properties_content_type_trgm
        ON assets USING gin ((properties ->> 'content_type') gin_trgm_ops);
    SQL

    # `Folder#name ILIKE '%...%'` — used by folder-mode search and the
    # suggestions autocomplete.
    execute <<~SQL
      CREATE INDEX index_folders_on_name_trgm
        ON folders USING gin (name gin_trgm_ops);
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS index_folders_on_name_trgm"
    execute "DROP INDEX IF EXISTS index_assets_on_properties_content_type_trgm"
    execute "DROP INDEX IF EXISTS index_assets_on_properties_text_trgm"
    execute "DROP INDEX IF EXISTS index_assets_on_properties_original_filename_trgm"
    execute "DROP INDEX IF EXISTS index_assets_on_title_trgm"
    disable_extension "pg_trgm" if extension_enabled?("pg_trgm")
  end
end
