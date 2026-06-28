# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Api::V1::Copilot (Semantic Search)", type: :request do
  # ===========================================================================
  # COPILOT SEARCH — POST /api/v1/copilot/search
  # ===========================================================================
  path "/api/v1/copilot/search" do
    post "Semantic (vector) search powered by the AI Gateway" do
      tags        "AI Copilot"
      consumes    "application/json"
      produces    "application/json"
      security    [ Bearer: [] ]
      description <<~DESC
        Translates a natural-language query into a dense vector via the AI Gateway
        (`POST /api/embed_query`) and performs an HNSW nearest-neighbour search
        using pgvector.

        Returns the top N most semantically similar assets (default 20, max 50)
        enriched with `similarity_score` (0–1, higher = closer match),
        `content_type`, `folder_name`, `tags`, and a resolved `url`.

        **Requires the Python AI Gateway to be running** (default: `localhost:8000`).
        Falls back with `503` when the gateway is unreachable.

        ## Optional params
        - `limit`        — 1–50 (default 20)
        - `content_type` — filter prefix: `"image"`, `"video"`, `"document"`, `"audio"`
      DESC

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[messages],
        properties: {
          query: {
            type:        :string,
            example:     "outdoor lifestyle photography with warm autumn tones",
            description: "Natural-language description of the assets you are looking for",
          },
          limit: {
            type:        :integer,
            example:     20,
            description: "Maximum results to return (1–50). Defaults to 20.",
          },
          content_type: {
            type:        :string,
            example:     "image",
            description: "Optional MIME-type prefix filter: image | video | document | audio",
          },
        },
      }

      # ── Asset item schema (reused in both response blocks) ──────────────────
      let(:asset_item_schema) do
        {
          type:       :object,
          properties: {
            id:                { type: :integer },
            title:             { type: :string },
            original_filename: { type: :string },
            status:            { type: :string },
            content_type:      { type: :string, nullable: true },
            file_size:         { type: :integer, nullable: true },
            width:             { type: :integer, nullable: true },
            height:            { type: :integer, nullable: true },
            folder_name:       { type: :string, nullable: true },
            folder_id:         { type: :integer, nullable: true },
            tags:              { type: :array, items: { type: :string } },
            description:       { type: :string, nullable: true },
            campaign:          { type: :string, nullable: true },
            url:               { type: :string, nullable: true },
            similarity_score:  { type: :number, nullable: true, example: 0.87,
                                 description: "1 - cosine_distance; 1.0 = perfect match, null when embedding unavailable." },
          },
        }
      end

      response "200", "Semantic search results returned (may be empty array)" do
        schema type: :object,
               required: %w[query count results],
               properties: {
                 query:   { type: :string },
                 count:   { type: :integer },
                 results: { type: :array, items: { type: :object } },
               }

        before do
          # Stub gateway so the spec never dials localhost:8000
          fake_conn = instance_double(Faraday::Connection)
          fake_resp = instance_double(Faraday::Response,
            success?: true,
            body: { "vector" => Array.new(384, 0.1) })
          allow(Faraday).to receive(:new).and_return(fake_conn)
          allow(fake_conn).to receive(:post).and_return(fake_resp)
        end

        let(:payload) { { query: "outdoor lifestyle photography" } }
        run_test!
      end

      response "200", "Empty result when query is blank" do
        let(:payload) { { query: "" } }
        run_test!
      end

      response "401", "Unauthenticated" do
        let(:payload) { { query: "test" } }
        run_test!
      end

      response "503", "AI Gateway unreachable" do
        schema type: :object,
               properties: { error: { type: :string } }
        before do
          allow(Faraday).to receive(:new).and_raise(Faraday::ConnectionFailed.new("Connection refused"))
        end
        let(:payload) { { query: "outdoor photography" } }
        run_test!
      end
    end
  end
end
