# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::Search', type: :request do
  # ── GET /api/v1/search ───────────────────────────────────────────────────────
  path '/api/v1/search' do
    get 'Full-text and faceted asset search' do
      tags        'Search'
      produces    'application/json'
      security    [ Bearer: [] ]
      description <<~DESC
        Performs lexical full-text search across asset `title`, `original_filename`,
        and **all JSONB metadata properties**. Supports mode filtering, schema filtering,
        and arbitrary dynamic metadata filters via query params.

        Returns facets alongside results so UIs can render live filter panels with
        a single request.

        ### Dynamic metadata filtering
        Any query param not in the reserved list (`q`, `mode`, `schema_id`) is
        treated as a JSONB property filter:
        ```
        GET /api/v1/search?brand=Nike&campaign=Summer2026
        ```
      DESC

      parameter name: :q, in: :query, type: :string, required: false,
                description: 'Full-text search term matched against title, filename, and all metadata values'
      parameter name: :mode, in: :query, type: :string, required: false,
                schema: { enum: %w[images files] },
                description: '`images` — image/* types only (default). `files` — non-image types only. Omit for all.'
      parameter name: :schema_id, in: :query, type: :integer, required: false,
                description: 'Filter to assets that have this metadata schema applied'

      response '200', 'search results with facets' do
        schema type: :object,
               properties: {
                 meta: {
                   type: :object,
                   properties: {
                     query:       { type: :string, nullable: true, example: 'brand logo' },
                     mode:        { type: :string, example: 'images' },
                     total_found: { type: :integer, example: 47 },
                     facets: {
                       type: :object,
                       properties: {
                         content_type: {
                           type: :array, items: { type: :string },
                           example: [ 'image/jpeg', 'image/png' ]
                         },
                         applied_schema: {
                           type: :array, items: { type: :string },
                           example: [ 'Product Images', 'Marketing Assets' ]
                         },
                       },
                     },
                   },
                 },
                 results: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:          { type: :integer, example: 1 },
                       uuid:        { type: :string, format: :uuid },
                       title:       { type: :string, example: 'Brand Logo Final' },
                       type:        { type: :string, example: 'image/png' },
                       size:        { type: :string, example: '2.4 MB' },
                       thumb_url:   { type: :string, nullable: true },
                       folder_id:   { type: :string, nullable: true },
                       schema_name: { type: :string, nullable: true },
                       schema_id:   { type: :integer, nullable: true },
                       metadata: {
                         type: :object,
                         description: 'Schema-driven metadata fields surfaced in search results',
                         properties: {
                           creator:     { type: :string, nullable: true },
                           title_meta:  { type: :string, nullable: true },
                           description: { type: :string, nullable: true },
                           sku:         { type: :string, nullable: true },
                           brand:       { type: :string, nullable: true },
                           asset_type:  { type: :string, nullable: true },
                           product_id:  { type: :string, nullable: true },
                           language:    { type: :string, nullable: true },
                           tags:        { type: :array, items: { type: :string }, nullable: true },
                         },
                       },
                     },
                   },
                 },
               }
        run_test!
      end
    end
  end
end
