# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::Copilot (Semantic Search)', type: :request do
  # ===========================================================================
  # COPILOT SEARCH — POST /api/v1/copilot/search
  # ===========================================================================
  path '/api/v1/copilot/search' do
    post 'Semantic (vector) search powered by the AI Gateway' do
      tags 'AI Copilot'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Translates a natural-language query into a 1536-dimension vector via the
        Python AI Gateway (`POST /api/embed_query`) and performs an HNSW nearest-
        neighbour search using pgvector. Returns the top 20 most semantically
        similar assets regardless of filename or metadata text.

        **Requires the Python AI Gateway to be running** (default: `localhost:8000`).
        Falls back gracefully with a 500 response if the gateway is unavailable.

        Use this endpoint to power "find me something like…" search experiences
        in your product.
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'query' ],
        properties: {
          query: {
            type: :string,
            example: 'outdoor lifestyle photography with warm autumn tones',
            description: 'Natural language description of the assets you are looking for',
          },
        },
      }

      response '200', 'Semantic search results returned (may be empty array)' do
        schema type: :object,
               properties: {
                 results: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:                { type: :integer },
                       original_filename: { type: :string },
                       file_url:          { type: :string, nullable: true },
                       properties:        { type: :object },
                     },
                   },
                 },
               }
        run_test!
      end

      response '500', 'AI Gateway is unreachable or returned an error' do
        schema type: :object,
               properties: { error: { type: :string, example: 'Failed to process semantic query.' } }
        run_test!
      end
    end
  end
end
