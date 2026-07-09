# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Folders coverage", type: :request do
  let(:user) { create(:user, :admin) }

  before do
    sign_in user
    allow(CdnInvalidationWorker).to receive(:perform_async) if defined?(CdnInvalidationWorker)
    allow(ApplySchemaToFolderJob).to receive(:perform_later) if defined?(ApplySchemaToFolderJob)
    allow(PropagateAccessPolicyJob).to receive(:perform_later) if defined?(PropagateAccessPolicyJob)
  end

  def json = response.parsed_body

  it "lists folders with computed paths and rejects signed-out requests" do
    parent = create(:folder, user: user, name: "Marketing")
    create(:folder, user: user, parent: parent, name: "Campaigns")

    get "/api/v1/folders", as: :json
    expect(response).to have_http_status(:ok)
    expect(json["folders"].map { |f| f["path"] }).to include("/Marketing", "/Marketing/Campaigns")

    sign_out user
    get "/api/v1/folders", as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "shows root folders/assets and creates root children from root parent_id" do
    create(:folder, user: user, name: "RootFolder")
    create(:asset, user: user, title: "Root Asset", properties: { "content_type" => "image/png" })

    get "/api/v1/folders/root", params: { sort: "type", direction: "desc" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json["breadcrumbs"]).to eq([ { "id" => "root", "name" => "Home" } ])
    expect(json["folders"].map { |f| f["name"] }).to include("RootFolder")

    post "/api/v1/folders", params: { folder: { name: "Created", parent_id: "root" } }, as: :json
    expect(response).to have_http_status(:created)
    expect(Folder.find(json["id"]).parent_id).to be_nil
  end

  it "shows nested folders with breadcrumbs and denies missing read permission" do
    parent = create(:folder, user: user, name: "Parent")
    child = create(:folder, user: user, parent: parent, name: "Child")
    create(:asset, user: user, folder: parent, title: "Parent Asset", properties: { "file_size" => 12 })

    get "/api/v1/folders/#{parent.id}", params: { sort: "size", direction: "desc" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json["breadcrumbs"].map { |crumb| crumb["name"] }).to eq(%w[Home Parent])
    expect(json["folders"].first).to include("id" => child.id, "asset_count" => 0)
    expect(json["assets"].first).to include("title" => "Parent Asset", "size" => 12)

    sign_in create(:user)
    get "/api/v1/folders/#{parent.id}", as: :json
    expect(response).to have_http_status(:forbidden)
    expect(json["error"]).to include("read")
  end

  it "updates folders and reports missing folders" do
    folder = create(:folder, user: user, name: "Old")

    patch "/api/v1/folders/#{folder.id}", params: { folder: { name: "New", description: "Updated" } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json).to include("name" => "New", "description" => "Updated")

    patch "/api/v1/folders/00000000-0000-0000-0000-000000000000", params: { folder: { name: "Nope" } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(json).to eq("error" => "Folder not found")
  end

  it "returns assigned profiles, direct schema and explicit policies" do
    folder = create(:folder, user: user)
    image_profile = create(:image_profile, :with_swatch, name: "Image Rules")
    video_profile = create(:video_profile, :with_adaptive_presets, name: "Video Rules")
    schema = create(:metadata_schema, :with_basic_tab, name: "Folder Schema")
    group = create(:user_group, name: "Editors")
    ImageProfileFolderAssignment.create!(image_profile: image_profile, folder_id: folder.id)
    VideoProfileFolderAssignment.create!(video_profile: video_profile, folder_id: folder.id)
    create(:metadata_schema_folder_assignment, metadata_schema: schema, folder_id: folder.id)
    create(:folder_policy, folder: folder, user_group: group, manage_access: true)

    get "/api/v1/folders/#{folder.id}/profiles", as: :json
    expect(response).to have_http_status(:ok)
    expect(json["image_profile"]).to include("name" => "Image Rules", "swatch_enabled" => true)
    expect(json["video_profile"]).to include("name" => "Video Rules", "preset_count" => 3)
    expect(json["metadata_schema"]).to include("name" => "Folder Schema", "source" => "direct")
    expect(json["policies"].first).to include("group_name" => "Editors", "manage_access" => true)
  end

  it "returns create validation errors" do
    post "/api/v1/folders", params: { folder: { name: "" } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "returns schema assignment states and applies/removes schemas" do
    folder = create(:folder, user: user)
    schema = create(:metadata_schema, name: "Product Schema")

    get "/api/v1/folders/#{folder.id}/schema", as: :json
    expect(response).to have_http_status(:ok)
    expect(json).to include("schema" => nil, "source" => "none")

    post "/api/v1/folders/#{folder.id}/apply_schema", params: { schema_id: schema.id, cascade: "false" }, as: :json
    expect(response).to have_http_status(:accepted)
    expect(json).to include("schema_id" => schema.id, "cascade" => false)

    post "/api/v1/folders/#{folder.id}/apply_schema", params: { schema_id: "0" }, as: :json
    expect(response).to have_http_status(:not_found)

    delete "/api/v1/folders/#{folder.id}/remove_schema", as: :json
    expect(response).to have_http_status(:ok)
  end

  it "handles root and missing folder schema lookups and root schema application" do
    schema = create(:metadata_schema, name: "Root Schema")
    assignment = create(:metadata_schema_folder_assignment, folder_id: create(:folder, user: user).id, metadata_schema: schema)
    assignment.update_column(:folder_id, "")

    get "/api/v1/folders/root/schema", as: :json
    expect(response).to have_http_status(:ok)
    expect(json).to include("source" => "direct", "schema" => a_hash_including("id" => schema.id))

    schema.update_column(:deleted_at, Time.current)
    get "/api/v1/folders/root/schema", as: :json
    expect(json).to eq("schema" => nil, "source" => "direct")

    get "/api/v1/folders/#{SecureRandom.uuid}/schema", as: :json
    expect(json).to eq("schema" => nil, "source" => "none")

    active_schema = create(:metadata_schema, name: "Fresh Root Schema")
    post "/api/v1/folders/root/apply_schema", params: { schema_id: active_schema.id }, as: :json
    expect(response).to have_http_status(:accepted)
    expect(ApplySchemaToFolderJob).to have_received(:perform_later).with(
      folder_id: "",
      schema_id: active_schema.id,
      cascade: true,
      initiated_by: user.id
    )

    delete "/api/v1/folders/root/remove_schema", as: :json
    expect(response).to have_http_status(:ok)
    expect(MetadataSchemaFolderAssignment.where(folder_id: "")).to be_empty
  end

  it "returns inherited schemas for descendants and none for an unassigned root" do
    parent = create(:folder, user: user, name: "Parent")
    child = create(:folder, user: user, parent: parent, name: "Child")
    schema = create(:metadata_schema, name: "Inherited Schema")
    create(:metadata_schema_folder_assignment, folder_id: parent.id, metadata_schema: schema)

    get "/api/v1/folders/#{child.id}/schema", as: :json
    expect(response).to have_http_status(:ok)
    expect(json).to include("source" => "inherited", "schema" => a_hash_including("id" => schema.id))

    MetadataSchemaFolderAssignment.where(folder_id: "").delete_all
    get "/api/v1/folders/root/schema", as: :json
    expect(json).to eq("schema" => nil, "source" => "none")
  end

  it "returns explicit and inherited policies and handles missing folders" do
    group = create(:user_group, name: "Marketing")
    parent = create(:folder, user: user, name: "Parent")
    child = create(:folder, user: user, parent: parent, name: "Child")
    create(:folder_policy, folder: parent, user_group: group, read_access: true)

    get "/api/v1/folders/#{child.id}/policies", as: :json
    expect(response).to have_http_status(:ok)
    expect(json["inherited_policies"].first["group_name"]).to eq("Marketing")

    get "/api/v1/folders/0/policies", as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "skips duplicate inherited groups and merges active version data" do
    parent = create(:folder, user: user, name: "Parent")
    child = create(:folder, user: user, parent: parent, name: "Child")
    editors = create(:user_group, name: "Editors")
    create(:folder_policy, folder: parent, user_group: editors, read_access: true)
    create(:folder_policy, folder: child, user_group: editors, manage_access: true)

    asset = create(:asset, user: user, folder: parent, title: "Versioned", properties: { "file_size" => 7 })
    version = create(:asset_version, asset: asset, version_number: 3, properties: { "content_type" => "image/jpeg", "file_size" => 42 })
    asset.update_column(:active_version_id, version.id)

    get "/api/v1/folders/#{child.id}/policies", as: :json
    expect(response).to have_http_status(:ok)
    expect(json["inherited_policies"].map { |row| row["group_id"] }).not_to include(editors.id)

    get "/api/v1/folders/#{parent.id}", as: :json
    payload = json["assets"].find { |entry| entry["id"] == asset.id }
    expect(payload).to include("version" => 3, "content_type" => "image/jpeg", "size" => 42)
    expect(payload.fetch("properties")).to include("content_type" => "image/jpeg", "file_size" => 42)
  end

  it "upserts and removes folder policies including cascade branch" do
    folder = create(:folder, user: user)
    group = create(:user_group)

    post "/api/v1/folders/#{folder.id}/policies", params: {
      group_id: group.id, read_access: true, manage_access: true, cascade: true
    }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json["policy"]["read_access"]).to be(true)

    post "/api/v1/folders/#{folder.id}/policies", params: { group_id: 0 }, as: :json
    expect(response).to have_http_status(:not_found)

    delete "/api/v1/folders/#{folder.id}/policies/#{group.id}", params: { cascade: true }, as: :json
    expect(response).to have_http_status(:ok)

    delete "/api/v1/folders/#{folder.id}/policies/#{group.id}", as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "restores and permanently deletes trashed folders" do
    folder = create(:folder, :trashed, user: user)
    post "/api/v1/folders/#{folder.id}/restore", as: :json
    expect(response).to have_http_status(:ok)
    expect(folder.reload.deleted_at).to be_nil

    folder.soft_delete
    delete "/api/v1/folders/#{folder.id}/permanent", as: :json
    expect(response).to have_http_status(:ok)
    expect(Folder.where(id: folder.id)).to be_empty
  end

  it "soft deletes folders and queues CDN invalidation" do
    folder = create(:folder, user: user)

    delete "/api/v1/folders/#{folder.id}", as: :json

    expect(response).to have_http_status(:ok)
    expect(folder.reload.deleted_at).to be_present
    expect(CdnInvalidationWorker).to have_received(:perform_async).with("folder", folder.id)
  end

  describe "folder-contents caching (FolderContentsCache)" do
    # FolderContentsCache.fetch short-circuits to an uncached yield in the
    # test environment (see the class's own spec for direct Redis-path
    # coverage), so here we verify the *integration*: #show always builds the
    # payload via FolderContentsCache.fetch (with the folder id + sort params),
    # permission checks still run before the cache is touched, and mutating
    # actions call FolderContentsCache.bust with the right folder id(s).

    it "wraps #show in FolderContentsCache.fetch keyed by folder id and sort/direction params" do
      folder = create(:folder, user: user)

      expect(FolderContentsCache).to receive(:fetch)
        .with(folder.id, params: { sort: "name", direction: "asc" })
        .and_call_original

      get "/api/v1/folders/#{folder.id}", params: { sort: "name", direction: "asc" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "enforces the read permission check before ever touching the cache" do
      other_user = create(:user)
      folder = create(:folder, user: user)

      expect(FolderContentsCache).not_to receive(:fetch)

      sign_in other_user
      get "/api/v1/folders/#{folder.id}", as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "busts the parent folder's cache on create/update/destroy/restore" do
      parent = create(:folder, user: user)

      expect(FolderContentsCache).to receive(:bust).with(nil)
      post "/api/v1/folders", params: { folder: { name: "New", parent_id: "root" } }, as: :json
      expect(response).to have_http_status(:created)

      expect(FolderContentsCache).to receive(:bust).with([ nil, parent.id ])
      new_child = create(:folder, user: user)
      patch "/api/v1/folders/#{new_child.id}", params: { folder: { name: "Renamed", parent_id: parent.id } }, as: :json
      expect(response).to have_http_status(:ok)

      expect(FolderContentsCache).to receive(:bust).with(parent.parent_id)
      delete "/api/v1/folders/#{parent.id}", as: :json
      expect(response).to have_http_status(:ok)

      expect(FolderContentsCache).to receive(:bust).with(parent.parent_id)
      post "/api/v1/folders/#{parent.id}/restore", as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
