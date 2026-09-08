# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Search query builder", type: :request do
  let(:user) { create(:user) }
  let(:folder) { create(:folder) }

  def json = response.parsed_body

  before { sign_in user }

  let!(:jpeg) do
    create(:asset, title: "Sunset over Rome", folder: folder, status: :approved,
                   properties: { "content_type" => "image/jpeg", "file_size" => "2048",
                                 "tags" => %w[travel sunset] })
  end

  let!(:png) do
    create(:asset, title: "Studio portrait", folder: folder, status: :ready,
                   properties: { "content_type" => "image/png", "file_size" => "512",
                                 "tags" => %w[portrait] })
  end

  describe "GET /api/v1/search/fields" do
    it "requires authentication" do
      sign_out user
      get "/api/v1/search/fields"
      expect(response).to have_http_status(:unauthorized)
    end

    it "serves the allow-list with an operator set per field" do
      get "/api/v1/search/fields"

      expect(response).to have_http_status(:ok)
      names = json["fields"].map { |f| f["name"] }
      expect(names).to include("title", "status", "file_size", "tags", "created_at")

      status_field = json["fields"].find { |f| f["name"] == "status" }
      expect(status_field["type"]).to eq("enum")
      expect(status_field["values"]).to include("approved", "draft")
      expect(status_field["operators"]).to include("eq", "in")
      expect(status_field["operators"]).not_to include("contains")
    end

    it "never exposes internal property keys" do
      names = (get("/api/v1/search/fields") && json["fields"].map { |f| f["name"] })
      expect(names).not_to include("checksum_sha256", "storage_path", "thumbnail_data")
    end

    it "publishes the limits so the builder can stop a user before the server does" do
      get "/api/v1/search/fields"
      expect(json["limits"]).to include("max_depth", "max_nodes", "max_list_values")
    end
  end

  describe "POST /api/v1/search/count" do
    it "counts matches without returning rows" do
      post "/api/v1/search/count", params: {
        query: { field: "content_type", operator: "eq", value: "image/jpeg" },
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to eq("count" => 1)
    end

    it "counts a nested boolean query" do
      post "/api/v1/search/count", params: {
        query: {
          op: "and",
          children: [
            { op: "or", children: [
              { field: "content_type", operator: "eq", value: "image/jpeg" },
              { field: "content_type", operator: "eq", value: "image/png" },
            ] },
            { op: "not", children: [ { field: "status", operator: "eq", value: "approved" } ] },
          ],
        },
      }, as: :json

      expect(json["count"]).to eq(1)
    end

    it "reports an invalid query as 422 with the path to the bad node" do
      post "/api/v1/search/count", params: {
        query: { op: "and", children: [ { field: "checksum_sha256", operator: "eq", value: "x" } ] },
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to match(/Unknown field/)
      expect(json["path"]).to eq(%w[children 0])
    end

    it "rejects an over-deep query rather than executing it" do
      deep = (Search::QueryCompiler::MAX_DEPTH + 2).times.inject(
        { field: "title", operator: "eq", value: "x" },
      ) { |inner, _| { op: "and", children: [ inner ] } }

      post "/api/v1/search/count", params: { query: deep }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to match(/too deeply/)
    end

    it "requires authentication" do
      sign_out user
      post "/api/v1/search/count", params: { query: {} }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/search with an AST" do
    it "filters results by the compiled query" do
      get "/api/v1/search", params: {
        query: { field: "tags", operator: "has_any", value: [ "sunset" ] }.to_json,
      }

      expect(response).to have_http_status(:ok)
      expect(json["results"].map { |r| r["title"] }).to contain_exactly("Sunset over Rome")
    end

    it "composes with the existing flat params rather than replacing them" do
      # The facet bar and the query builder both narrow; layering them is what
      # "these filters, plus this query" means on the screen.
      get "/api/v1/search", params: {
        publish_status: "published",
        query: { field: "content_type", operator: "starts_with", value: "image/" }.to_json,
      }

      # `published` is ready|approved, so both assets qualify on the flat param.
      expect(json["results"].size).to eq(2)

      get "/api/v1/search", params: {
        approved_status: "approved",
        query: { field: "content_type", operator: "starts_with", value: "image/" }.to_json,
      }
      expect(json["results"].map { |r| r["title"] }).to contain_exactly("Sunset over Rome")
    end

    it "does not treat the query param as a dynamic property filter" do
      # `query` must be reserved; otherwise the AST's JSON string would be
      # compiled into `properties->>'query' IN (...)` and match nothing.
      get "/api/v1/search", params: {
        query: { field: "status", operator: "in", value: %w[ready approved] }.to_json,
      }

      expect(json["results"].size).to eq(2)
    end

    it "returns 422 for a malformed AST instead of silently ignoring it" do
      get "/api/v1/search", params: { query: "{not json" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to match(/not valid JSON/)
    end

    it "keeps distinct queries in distinct cache entries" do
      get "/api/v1/search", params: {
        query: { field: "content_type", operator: "eq", value: "image/jpeg" }.to_json,
      }
      first = json["results"].map { |r| r["title"] }

      get "/api/v1/search", params: {
        query: { field: "content_type", operator: "eq", value: "image/png" }.to_json,
      }
      second = json["results"].map { |r| r["title"] }

      expect(first).to contain_exactly("Sunset over Rome")
      expect(second).to contain_exactly("Studio portrait")
    end
  end
end
