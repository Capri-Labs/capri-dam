# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Collection routing", type: :integration, aggregate_failures: true do
  let(:admin_user) { create(:user, :admin) }
  let(:json_headers) do
    {
      "ACCEPT" => "application/json",
      "CONTENT_TYPE" => "application/json",
    }
  end

  before do
    sign_in admin_user
  end

  it "supports manual membership and smart-rule routing" do
    asset = create(:asset, user: admin_user, status: :ready, title: "Manual Collection Asset")

    post "/api/v1/collections",
         params: { collection: { name: "Manual Collection", collection_type: "manual" } }.to_json,
         headers: json_headers
    expect(response).to have_http_status(:created)
    manual_collection = Collection.find(json_body.fetch("id"))

    post "/api/v1/collections/#{manual_collection.slug}/assets/#{asset.id}",
         headers: { "ACCEPT" => "application/json" }
    expect(response).to have_http_status(:ok)

    get "/api/v1/collections/#{manual_collection.slug}"
    expect(response).to have_http_status(:ok)
    assets = json_body.fetch("collection_assets").map { |entry| entry.fetch("asset").fetch("id") }
    expect(assets).to include(asset.id)

    post "/api/v1/collections",
         params: { collection: { name: "Smart Collection", collection_type: "smart" } }.to_json,
         headers: json_headers
    expect(response).to have_http_status(:created)
    smart_collection = Collection.find(json_body.fetch("id"))

    post "/api/v1/collections/#{smart_collection.slug}/rule",
         params: {
           semantic_prompt: "integration campaign",
           similarity_threshold: 0.8,
           metadata_filters: { "campaign" => "spring" },
           active: true,
         }.to_json,
         headers: json_headers
    expect(response).to have_http_status(:ok)

    routed_asset = create(
      :asset,
      user: admin_user,
      status: :ready,
      title: "Smart Routed Asset",
      properties: { "campaign" => "spring" }
    )

    stub_const("VectorCalculator", Class.new do
      def self.cosine_similarity(*)
        0.95
      end
    end)

    Asset.class_eval do
      def vector_embedding
        [ 0.9 ]
      end
    end unless Asset.method_defined?(:vector_embedding)

    CollectionRule.class_eval do
      def prompt_vector
        [ 0.9 ]
      end
    end unless CollectionRule.method_defined?(:prompt_vector)

    SmartCollectionRouterWorker.new.perform(routed_asset.id)

    get "/api/v1/collections/#{smart_collection.slug}"
    expect(response).to have_http_status(:ok)
    smart_assets = json_body.fetch("collection_assets").map { |entry| entry.fetch("asset").fetch("id") }
    expect(smart_assets).to include(routed_asset.id)
  end
end
