# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Copilot coverage", type: :request do
  let(:user) { create(:user) }
  let(:gateway_url) { "http://localhost:8000" }

  before do
    sign_in user
    allow(Redis).to receive(:new).and_return(instance_double(Redis, publish: true))
    allow_any_instance_of(AssetUrlHelper).to receive(:asset_url_for) { |_, asset| "/api/v1/assets/local/#{asset.uuid}" }
  end

  around do |example|
    unless Asset.method_defined?(:original_filename)
      Asset.define_method(:original_filename) { properties["original_filename"] }
      example.run
      Asset.remove_method(:original_filename)
    else
      example.run
    end
  end

  describe "POST /api/v1/copilot/search" do
    it "embeds the query, filters by content type, clamps the limit, and returns serialized assets" do
      folder = create(:folder, name: "Launch", user: user)
      asset = create(:asset, user: user, folder: folder, title: "Autumn Hero", properties: {
        "original_filename" => "hero.jpg",
        "tags" => [ "fall" ],
        "description" => "Warm product scene",
        "campaign" => "Q4",
      })
      version = create(:asset_version, asset: asset, properties: {
        "content_type" => "image/jpeg",
        "file_size" => 1234,
        "width" => 640,
        "height" => 480,
      })
      asset.update!(active_version: version)

      stub_request(:post, "#{gateway_url}/api/embed_query")
        .with(body: { text: "warm autumn product" }.to_json)
        .to_return(status: 200, body: { vector: Array.new(1536, 0.01) }.to_json, headers: { "Content-Type" => "application/json" })

      relation = Asset.where(id: asset.id).select("assets.*, 0.125 AS neighbor_distance")
      allow(Asset).to receive(:nearest_to_vector).and_return(relation)

      post "/api/v1/copilot/search", params: { query: " warm autumn product ", limit: 500, content_type: "image" }, as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["query"]).to eq("warm autumn product")
      expect(json["count"]).to eq(1)
      expect(json["results"].first).to include(
        "title" => "Autumn Hero",
        "original_filename" => "hero.jpg",
        "content_type" => "image/jpeg",
        "folder_name" => "Launch",
        "similarity_score" => "0.875"
      )
      expect(json["results"].first["tags"]).to eq([ "fall" ])
    end

    it "returns an empty result for a missing query without calling the gateway" do
      post "/api/v1/copilot/search", params: {}, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("results" => [], "query" => "")
    end

    it "returns 503 when the AI gateway times out" do
      stub_request(:post, "#{gateway_url}/api/embed_query").to_timeout

      post "/api/v1/copilot/search", params: { query: "outdoor" }, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body)["error"]).to include("AI Gateway unavailable")
    end

    it "returns 401 when unauthenticated" do
      sign_out user

      post "/api/v1/copilot/search", params: { query: "outdoor" }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "#serialize_asset" do
    it "handles missing versions, folders, and similarity scores" do
      controller = Api::V1::CopilotsController.new
      asset = create(:asset, user: user, folder: nil, properties: { "original_filename" => "raw.bin" })

      result = controller.send(:serialize_asset, asset)

      expect(result).to include(
        title: asset.title,
        folder_name: nil,
        content_type: nil,
        similarity_score: nil
      )
    end
  end

  describe "#fetch_query_embedding" do
    it "raises when the gateway returns a non-success response" do
      controller = Api::V1::CopilotsController.new
      response = instance_double(Faraday::Response, success?: false, status: 502)
      allow(controller).to receive(:gateway_client).and_return(instance_double(Faraday::Connection, post: response))

      expect { controller.send(:fetch_query_embedding, "broken") }.to raise_error("AI Gateway Error: 502")
    end
  end
end
