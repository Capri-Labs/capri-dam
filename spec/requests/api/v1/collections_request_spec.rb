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

  it "resolves asset_id by the public uuid column (as returned by search suggestions), not just the primary key" do
    collection = create(:collection, user: user)
    asset = create(:asset, user: user)

    # Search suggestions/other client-facing endpoints hand back `asset.uuid`
    # (not the DB primary key `id`), so add/pin/remove must accept either.
    post "/api/v1/collections/#{collection.slug}/assets/#{asset.uuid}", as: :json
    expect(response).to have_http_status(:ok)
    expect(collection.assets.reload).to include(asset)

    patch "/api/v1/collections/#{collection.slug}/assets/#{asset.uuid}/pin", as: :json
    expect(response).to have_http_status(:ok)
    expect(json["pinned"]).to be(true)

    delete "/api/v1/collections/#{collection.slug}/assets/#{asset.uuid}", as: :json
    expect(response).to have_http_status(:ok)
    expect(collection.assets.reload).not_to include(asset)
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

  it "mints a signed, expiring public share link for a collection" do
    collection = create(:collection, user: user)

    post "/api/v1/collections/#{collection.slug}/share_link", as: :json

    expect(response).to have_http_status(:ok)
    expect(json["token"]).to be_present
    expect(json["url"]).to include("/s/collections/#{json["token"]}")
    expect(Time.zone.parse(json["expires_at"])).to be_within(1.minute).of(Collection::SHARE_LINK_EXPIRY.from_now)
    expect(Collection.find_by_share_token(json["token"])).to eq(collection)
  end

  it "requires authentication to mint a share link" do
    collection = create(:collection, user: user)
    sign_out user

    post "/api/v1/collections/#{collection.slug}/share_link", as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it "configures metadata and hybrid smart rules alongside the legacy semantic mode" do
    collection = create(:collection, user: user)

    post "/api/v1/collections/#{collection.slug}/rule",
         params: { match_mode: "metadata", metadata_filters: { "status" => "approved" }, active: true }, as: :json
    expect(response).to have_http_status(:ok)
    expect(collection.reload.collection_rule.match_mode).to eq("metadata")
    expect(collection.collection_rule.metadata_filters).to eq({ "status" => "approved" })

    # Reconfiguring with only metadata_filters (no semantic_prompt key sent at
    # all) must NOT null out anything since match_mode stays metadata-only.
    patch_params = { metadata_filters: { "status" => "rejected" } }
    post "/api/v1/collections/#{collection.slug}/rule", params: patch_params, as: :json
    expect(response).to have_http_status(:ok)
    expect(collection.reload.collection_rule.metadata_filters).to eq({ "status" => "rejected" })
  end

  it "runs a real (non-mocked) metadata dry-run preview via simulate_rule" do
    matching = create(:asset, user: user, properties: { "status" => "approved" })
    create(:asset, user: user, properties: { "status" => "rejected" })

    post "/api/v1/collections/simulate_rule", params: { metadata_filters: { status: "approved" } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(json["matches"].map { |m| m["id"] }).to include(matching.id)
    expect(json["matches"].map { |m| m["id"] }).not_to include(be_nil)
  end

  describe "access governance policies" do
    it "lists, upserts and removes group-scoped access policies" do
      collection = create(:collection, user: user)
      group = create(:user_group)

      get "/api/v1/collections/#{collection.slug}/policies", as: :json
      expect(response).to have_http_status(:ok)
      expect(json["policies"]).to eq([])

      post "/api/v1/collections/#{collection.slug}/policies",
           params: { group_id: group.id, view_access: true, edit_access: true }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json["policy"]["group_id"]).to eq(group.id)
      expect(json["policy"]["edit_access"]).to be(true)

      get "/api/v1/collections/#{collection.slug}/policies", as: :json
      expect(json["policies"].size).to eq(1)

      delete "/api/v1/collections/#{collection.slug}/policies/#{group.id}", as: :json
      expect(response).to have_http_status(:ok)
      expect(collection.collection_policies.count).to eq(0)
    end

    it "returns not_found for an unknown group or policy" do
      collection = create(:collection, user: user)

      post "/api/v1/collections/#{collection.slug}/policies", params: { group_id: 0 }, as: :json
      expect(response).to have_http_status(:not_found)

      delete "/api/v1/collections/#{collection.slug}/policies/0", as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "restricts non-owner, non-admin, non-collection-admin users from managing/deleting a workspace once policies exist" do
      owner = create(:user, admin: false)
      viewer_group = create(:user_group)
      viewer = create(:user, admin: false)
      viewer.user_groups << viewer_group

      collection = create(:collection, user: owner)
      create(:collection_policy, :viewer, collection: collection, user_group: viewer_group)

      sign_in viewer

      post "/api/v1/collections/#{collection.slug}/rule", params: { semantic_prompt: "x" }, as: :json
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/collections/#{collection.slug}", as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "allows a collection-admin (via group admin_access) to configure rules and delete the workspace" do
      owner = create(:user, admin: false)
      admin_group = create(:user_group)
      collection_admin = create(:user, admin: false)
      collection_admin.user_groups << admin_group

      collection = create(:collection, user: owner)
      create(:collection_policy, :collection_admin, collection: collection, user_group: admin_group)

      sign_in collection_admin

      post "/api/v1/collections/#{collection.slug}/rule", params: { semantic_prompt: "x" }, as: :json
      expect(response).to have_http_status(:ok)

      delete "/api/v1/collections/#{collection.slug}", as: :json
      expect(response).to have_http_status(:ok)
    end

    it "allows an editor (via group edit_access) to update the workspace but not delete it or configure rules" do
      owner = create(:user, admin: false)
      editor_group = create(:user_group)
      editor = create(:user, admin: false)
      editor.user_groups << editor_group

      collection = create(:collection, user: owner)
      create(:collection_policy, :editor, collection: collection, user_group: editor_group)

      sign_in editor

      patch "/api/v1/collections/#{collection.slug}", params: { collection: { description: "Edited" } }, as: :json
      expect(response).to have_http_status(:ok)

      delete "/api/v1/collections/#{collection.slug}", as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
