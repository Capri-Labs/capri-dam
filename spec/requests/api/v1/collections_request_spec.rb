# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Collections coverage", type: :request do
  let(:user) { create(:user, :admin) }
  before { sign_in user }
  def json = response.parsed_body

  it "lists active collections with as_of and pinned_for_asset flags and requires auth" do
    asset = create(:asset, user: user)
    old = create(:collection, user: user, name: "Old")
    create(:collection_asset, collection: old, asset: asset)
    expired = create(:collection, user: user, name: "Expired", expires_at: 1.day.ago)

    get "/api/v1/collections", params: { as_of: Time.current.iso8601, asset_id: asset.id }, as: :json
    expect(response).to have_http_status(:ok)
    names = json.map { |c| c["name"] }
    expect(names).to include("Old")
    expect(names).not_to include(expired.name)
    expect(json.find { |c| c["id"] == old.id }["pinned_for_asset"]).to be(true)

    sign_out user
    get "/api/v1/collections", as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "creates, updates, shows and archives collections including validation failure" do
    post "/api/v1/collections", params: { collection: { name: "Campaign", properties: { tags: [ "summer" ] } } }, as: :json
    expect(response).to have_http_status(:created)
    slug = json["slug"]

    post "/api/v1/collections", params: { collection: { name: "" } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    patch "/api/v1/collections/#{slug}", params: { collection: { description: "Updated" } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json["description"]).to eq("Updated")

    get "/api/v1/collections/#{slug}", params: { as_of: Time.current.iso8601 }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json["name"]).to eq("Campaign")

    delete "/api/v1/collections/#{slug}", as: :json
    expect(response).to have_http_status(:ok)
    expect(Collection.find_by(slug: slug).deleted_at).to be_present
  end

  it "returns validation errors when updating a collection with invalid attributes" do
    collection = create(:collection, user: user, name: "Campaign")

    patch "/api/v1/collections/#{collection.slug}", params: { collection: { name: "" } }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["errors"]).to be_present
  end

  it "handles missing and forbidden collections" do
    get "/api/v1/collections/missing", as: :json
    expect(response).to have_http_status(:not_found)

    sign_in create(:user)
    restricted = create(:collection, user: user, properties: { allowed_groups: [ "Nobody" ], denied_groups: [] })
    get "/api/v1/collections/#{restricted.slug}", as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "bulk updates and bulk deletes while preserving existing properties" do
    a = create(:collection, user: user, properties: { "tags" => [ "old" ], "allowed_groups" => [] })
    b = create(:collection, user: user)

    patch "/api/v1/collections/bulk_update", params: { ids: [ a.id, b.id ], collection: { properties: { denied_groups: [ "Blocked" ] } } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(a.reload.properties["tags"]).to eq([ "old" ])
    expect(a.properties["denied_groups"]).to eq([ "Blocked" ])

    patch "/api/v1/collections/bulk_update", params: { collection: { description: "x" } }, as: :json
    expect(response).to have_http_status(:bad_request)

    delete "/api/v1/collections/bulk_delete", params: { ids: [ a.id, b.id ] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(Collection.where(id: [ a.id, b.id ]).pluck(:deleted_at)).to all(be_present)

    delete "/api/v1/collections/bulk_delete", as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it "surfaces bulk update failures" do
    collection = create(:collection, user: user)

    allow(Collection).to receive(:where).and_call_original
    allow(Collection).to receive(:where).with(id: [ collection.id ]).and_raise(StandardError, "boom")

    patch "/api/v1/collections/bulk_update", params: { ids: [ collection.id ], collection: { description: "x" } }, as: :json

    expect(response).to have_http_status(:internal_server_error)
    expect(json).to eq("error" => "boom")
  end

  it "adds, rejects duplicate, pins, unpins and removes collection assets" do
    collection = create(:collection, user: user)
    asset = create(:asset, user: user)

    post "/api/v1/collections/#{collection.slug}/assets/#{asset.id}", as: :json
    expect(response).to have_http_status(:ok)

    post "/api/v1/collections/#{collection.slug}/assets/#{asset.id}", as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    patch "/api/v1/collections/#{collection.slug}/assets/#{asset.id}/pin", as: :json
    expect(response).to have_http_status(:ok)
    expect(json["pinned"]).to be(true)

    patch "/api/v1/collections/#{collection.slug}/assets/#{asset.id}/pin", as: :json
    expect(response).to have_http_status(:ok)
    expect(json["pinned"]).to be(false)

    delete "/api/v1/collections/#{collection.slug}/assets/#{asset.id}", as: :json
    expect(response).to have_http_status(:ok)

    delete "/api/v1/collections/#{collection.slug}/assets/#{asset.id}", as: :json
    expect(response).to have_http_status(:not_found)

    post "/api/v1/collections/#{collection.slug}/assets/0", as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "returns not found when toggling a pin for an asset outside the collection" do
    collection = create(:collection, user: user)
    asset = create(:asset, user: user)

    patch "/api/v1/collections/#{collection.slug}/assets/#{asset.id}/pin", as: :json

    expect(response).to have_http_status(:not_found)
    expect(json).to eq("error" => "Asset not in collection")
  end

  it "configures smart rules, cluster maps, purges CDN and simulates rules" do
    collection = create(:collection, user: user)
    asset = create(:asset, user: user, title: "Published", status: :ready)
    create(:collection_asset, collection: collection, asset: asset)

    post "/api/v1/collections/#{collection.slug}/rule", params: { semantic_prompt: "blue shoes", active: false }, as: :json
    expect(response).to have_http_status(:ok)
    expect(collection.reload.collection_type).to eq("smart")
    expect(collection.collection_rule.semantic_prompt).to eq("blue shoes")

    post "/api/v1/collections/#{collection.slug}/purge_cdn", as: :json
    expect(response).to have_http_status(:ok)

    get "/api/v1/collections/#{collection.slug}/cluster_map", as: :json
    expect(response).to have_http_status(:ok)
    expect(json["nodes"].first).to include("id" => asset.id, "title" => "Published")

    allow(Asset).to receive(:published).and_return(Asset.where(id: asset.id))
    post "/api/v1/collections/simulate_rule", params: { semantic_prompt: "product", similarity_threshold: 0.7 }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json["message"]).to eq("Simulation complete.")

    post "/api/v1/collections/simulate_rule", as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it "defaults smart rules to active and surfaces validation failures" do
    collection = create(:collection, user: user)

    post "/api/v1/collections/#{collection.slug}/rule", params: { semantic_prompt: "product shots" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(collection.reload.collection_rule.active).to be(true)

    post "/api/v1/collections/#{collection.slug}/rule", params: { semantic_prompt: "" }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["errors"]).to include("Semantic prompt can't be blank")
  end

  it "includes asset URLs in the cluster map when the asset object exposes them" do
    collection = create(:collection, user: user)
    asset = double("Asset", id: 101, title: "Published", original_filename: "published.jpg", url: "/api/v1/assets/local/example.jpg")
    allow(asset).to receive(:respond_to?).with(:url).and_return(true)
    allow_any_instance_of(Collection).to receive(:assets).and_return([ asset ])

    get "/api/v1/collections/#{collection.slug}/cluster_map", as: :json

    expect(response).to have_http_status(:ok)
    expect(json["nodes"]).to include(
      a_hash_including("id" => 101, "url" => "/api/v1/assets/local/example.jpg")
    )
  end

  it "surfaces archive failures" do
    collection = create(:collection, user: user)
    allow_any_instance_of(Collection).to receive(:update).and_return(false)

    delete "/api/v1/collections/#{collection.slug}", as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json).to eq("error" => "Failed to archive workspace.")
  end
end
