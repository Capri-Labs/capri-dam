# frozen_string_literal: true

require "rails_helper"

# Regression guard for the pg_trgm GIN indexes that back the lexical search
# `ILIKE` queries in `Api::V1::SearchController` (see
# db/migrate/20260716113000_add_trigram_search_indexes_for_lexical_search.rb,
# ADR 3 in docs/architecture/src/09_design_decisions.adoc, and the "Lexical
# search has no index" entry in docs/architecture/src/11_technical_risks.adoc).
#
# These indexes have no ActiveRecord-level model API to assert against (they
# back raw SQL `ILIKE`/`->>` expressions, not a column with a Rails-visible
# schema annotation), so this spec queries `pg_indexes` directly to make sure
# a future migration/schema reset can't silently drop them without a test
# failure calling it out.
RSpec.describe "Lexical search trigram indexes", type: :model do
  def index_exists?(table, index_name)
    ActiveRecord::Base.connection.select_value(
      "SELECT 1 FROM pg_indexes WHERE tablename = #{ActiveRecord::Base.connection.quote(table)} " \
      "AND indexname = #{ActiveRecord::Base.connection.quote(index_name)}"
    ).present?
  end

  it "has the pg_trgm extension enabled" do
    expect(ActiveRecord::Base.connection.extension_enabled?("pg_trgm")).to be true
  end

  it "indexes assets.title for ILIKE substring search" do
    expect(index_exists?("assets", "index_assets_on_title_trgm")).to be true
  end

  it "indexes properties->>'original_filename' for ILIKE substring search" do
    expect(index_exists?("assets", "index_assets_on_properties_original_filename_trgm")).to be true
  end

  it "indexes properties::text for the full-metadata ILIKE fallback" do
    expect(index_exists?("assets", "index_assets_on_properties_text_trgm")).to be true
  end

  it "indexes properties->>'content_type' for mime/mode prefix filters" do
    expect(index_exists?("assets", "index_assets_on_properties_content_type_trgm")).to be true
  end

  it "indexes folders.name for folder-mode ILIKE search" do
    expect(index_exists?("folders", "index_folders_on_name_trgm")).to be true
  end

  it "lets the planner use a bitmap index scan for the search controller's text query" do
    connection = ActiveRecord::Base.connection
    connection.execute("SET LOCAL enable_seqscan = off")

    plan = connection.exec_query(<<~SQL).rows.join("\n")
      EXPLAIN SELECT * FROM assets
      WHERE title ILIKE '%regression-guard%'
         OR properties->>'original_filename' ILIKE '%regression-guard%'
         OR properties::text ILIKE '%regression-guard%'
    SQL

    expect(plan).to include("Bitmap Index Scan")
    expect(plan).to include("index_assets_on_title_trgm")
  end
end
