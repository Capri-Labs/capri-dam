# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::FoldersController, type: :controller do
  include Devise::Test::ControllerHelpers

  let(:admin) { create(:user, :admin) }

  before do
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      scope module: "api/v1" do
        get "folders/:id" => "folders#show"
        patch "folders/:id" => "folders#update"
        get "folders/:id/profiles" => "folders#profiles"
        get "folders/:id/policies" => "folders#folder_policies"
        post "folders/:id/purge_cdn" => "folders#purge_folder_cdn"
        get "folders/:id/schema" => "folders#schema"
        post "folders/:id/apply_schema" => "folders#apply_schema"
        delete "folders/:id/remove_schema" => "folders#remove_schema"
        post "folders/:id/policies" => "folders#upsert_folder_policy"
        delete "folders/:id/policies/:group_id" => "folders#remove_folder_policy"
      end
    end

    request.env["devise.mapping"] = Devise.mappings[:user]
    sign_in admin
    allow(controller).to receive(:authenticate_hybrid!).and_return(true)
    allow(ApplySchemaToFolderJob).to receive(:perform_later)
    allow(CdnInvalidationWorker).to receive(:perform_async)
    allow(PropagateAccessPolicyJob).to receive(:perform_later)
  end

  describe "POST #purge_folder_cdn" do
    it "enqueues a folder CDN purge and returns a success message" do
      post :purge_folder_cdn, params: { id: SecureRandom.uuid }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("message" => "Folder CDN purge initiated.")
      expect(CdnInvalidationWorker).to have_received(:perform_async).with("folder", controller.params[:id])
    end
  end

  describe "GET #schema" do
    it "returns a directly assigned schema" do
      folder = create(:folder, user: admin)
      schema = create(:metadata_schema, :with_basic_tab, name: "Direct Schema")
      create(:metadata_schema_folder_assignment, metadata_schema: schema, folder_id: folder.id)

      get :schema, params: { id: folder.id }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "source" => "direct",
        "schema" => a_hash_including("id" => schema.id, "name" => "Direct Schema")
      )
    end

    it "returns an inherited schema from the closest ancestor" do
      parent = create(:folder, user: admin, name: "Parent")
      child = create(:folder, user: admin, parent: parent, name: "Child")
      schema = create(:metadata_schema, :with_basic_tab, name: "Inherited Schema")
      create(:metadata_schema_folder_assignment, metadata_schema: schema, folder_id: parent.id)

      get :schema, params: { id: child.id }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "source" => "inherited",
        "schema" => a_hash_including("id" => schema.id, "name" => "Inherited Schema")
      )
    end

    it "returns a direct source with a nil schema when the assigned schema is inactive" do
      folder = create(:folder, user: admin)
      schema = create(:metadata_schema, :with_basic_tab, name: "Inactive Schema", deleted_at: Time.current)
      create(:metadata_schema_folder_assignment, metadata_schema: schema, folder_id: folder.id)

      get :schema, params: { id: folder.id }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "schema" => nil,
        "source" => "direct"
      )
    end

    it "returns none for root and unknown folders without assignments" do
      get :schema, params: { id: "root" }, format: :json
      expect(response.parsed_body).to eq("schema" => nil, "source" => "none")

      get :schema, params: { id: SecureRandom.uuid }, format: :json
      expect(response.parsed_body).to eq("schema" => nil, "source" => "none")
    end
  end

  describe "POST #apply_schema" do
    it "queues root schema application without an authenticated current_user" do
      schema = create(:metadata_schema, :with_basic_tab, name: "Root Schema")
      allow(controller).to receive(:current_user).and_return(nil)

      post :apply_schema, params: { id: "root", schema_id: schema.id }, format: :json

      expect(response).to have_http_status(:accepted)
      expect(ApplySchemaToFolderJob).to have_received(:perform_later).with(
        folder_id: "",
        schema_id: schema.id,
        cascade: true,
        initiated_by: nil
      )
    end
  end

  describe "DELETE #remove_schema" do
    it "removes the root assignment" do
      # A root-level assignment (folder_id: "") can only exist as a legacy/edge
      # case row — ApplySchemaToFolderJob intentionally never creates one via
      # normal validated `create!`, and the model validates folder_id presence.
      # Build one directly, bypassing validations, to exercise the destroy path.
      assignment = build(:metadata_schema_folder_assignment, folder_id: "", metadata_schema: create(:metadata_schema))
      assignment.save!(validate: false)

      expect do
        delete :remove_schema, params: { id: "root" }, format: :json
      end.to change(MetadataSchemaFolderAssignment, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST #upsert_folder_policy" do
    let(:folder) { create(:folder, user: admin) }
    let(:group) { create(:user_group) }

    it "returns validation errors when the policy is invalid" do
      invalid_policy = build(:folder_policy, folder: folder, user_group: group)
      invalid_policy.errors.add(:read_access, "is invalid")
      allow(FolderPolicy).to receive(:find_or_initialize_by).and_return(invalid_policy)
      allow(invalid_policy).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(invalid_policy))

      post :upsert_folder_policy,
           params: { id: folder.id, group_id: group.id, read_access: true },
           format: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch("errors")).to include("Read access is invalid")
    end

    it "returns not found when the folder does not exist" do
      post :upsert_folder_policy,
           params: { id: SecureRandom.uuid, group_id: group.id, read_access: true },
           format: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Folder not found")
    end
  end

  describe "DELETE #remove_folder_policy" do
    let(:group) { create(:user_group) }

    it "returns not found when the folder does not exist" do
      delete :remove_folder_policy, params: { id: SecureRandom.uuid, group_id: group.id }, format: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "Folder not found")
    end
  end

  describe "GET #show" do
    let(:folder) { create(:folder, user: admin, name: "Parent") }

    it "reports subfolder counts excluding trashed children" do
      child = create(:folder, user: admin, parent: folder, name: "Child")
      create(:folder, user: admin, parent: child, name: "Visible grandchild")
      create(:folder, :trashed, user: admin, parent: child, name: "Hidden grandchild")

      get :show, params: { id: folder.id }, format: :json

      payload = response.parsed_body.fetch("folders").find { |entry| entry["id"] == child.id }
      expect(payload).to include("subfolder_count" => 1)
    end

    it "sorts folders by updated_at" do
      older = create(:folder, user: admin, parent: folder, name: "Older")
      newer = create(:folder, user: admin, parent: folder, name: "Newer")
      older.update_column(:updated_at, 2.days.ago)
      newer.update_column(:updated_at, 1.day.ago)

      get :show, params: { id: folder.id, sort: "updated_at", direction: "asc" }, format: :json

      expect(response.parsed_body.fetch("folders").map { |entry| entry["id"] }).to eq([ older.id, newer.id ])
    end

    it "sorts assets by created_at and updated_at and defaults to title order" do
      alpha = create(:asset, user: admin, folder: folder, title: "Alpha")
      beta = create(:asset, user: admin, folder: folder, title: "Beta")
      alpha.update_columns(created_at: 2.days.ago, updated_at: 1.day.ago)
      beta.update_columns(created_at: 1.day.ago, updated_at: 2.days.ago)

      get :show, params: { id: folder.id }, format: :json
      expect(response.parsed_body.fetch("assets").map { |entry| entry["title"] }).to eq(%w[Alpha Beta])

      get :show, params: { id: folder.id, sort: "created_at", direction: "asc" }, format: :json
      expect(response.parsed_body.fetch("assets").map { |entry| entry["id"] }).to eq([ alpha.id, beta.id ])

      get :show, params: { id: folder.id, sort: "updated_at", direction: "asc" }, format: :json
      expect(response.parsed_body.fetch("assets").map { |entry| entry["id"] }).to eq([ beta.id, alpha.id ])
    end

    it "merges active-version properties and version metadata into the payload" do
      asset = create(:asset, user: admin, folder: folder, title: "Versioned", properties: { "file_size" => 7 })
      version = create(:asset_version, asset: asset, version_number: 3, properties: { "content_type" => "image/jpeg", "file_size" => 42 })
      asset.update_column(:active_version_id, version.id)

      get :show, params: { id: folder.id }, format: :json

      payload = response.parsed_body.fetch("assets").find { |entry| entry["id"] == asset.id }
      expect(payload).to include(
        "version" => 3,
        "content_type" => "image/jpeg",
        "size" => 42
      )
      expect(payload.fetch("properties")).to include("content_type" => "image/jpeg", "file_size" => 42)
    end

    it "marks a PSD asset as not editable but a JPEG asset as editable" do
      psd = create(:asset, user: admin, folder: folder, title: "Artwork", properties: { "content_type" => "image/vnd.adobe.photoshop" })
      jpeg = create(:asset, user: admin, folder: folder, title: "Photo", properties: { "content_type" => "image/jpeg" })

      get :show, params: { id: folder.id }, format: :json

      assets = response.parsed_body.fetch("assets")
      expect(assets.find { |entry| entry["id"] == psd.id }["editable"]).to be(false)
      expect(assets.find { |entry| entry["id"] == jpeg.id }["editable"]).to be(true)
    end
  end

  describe "GET #profiles" do
    it "resolves inherited schemas while walking the folder tree" do
      grandparent = create(:folder, user: admin, name: "Grandparent")
      parent = create(:folder, user: admin, parent: grandparent, name: "Parent")
      child = create(:folder, user: admin, parent: parent, name: "Child")
      schema = create(:metadata_schema, :with_basic_tab, name: "Inherited Profile Schema")
      create(:metadata_schema_folder_assignment, metadata_schema: schema, folder_id: grandparent.id)

      get :profiles, params: { id: child.id }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("metadata_schema")).to include(
        "id" => schema.id,
        "name" => "Inherited Profile Schema",
        "source" => "inherited"
      )
    end
  end

  describe "GET #folder_policies" do
    it "skips duplicate inherited groups and serializes missing groups as nil" do
      parent = create(:folder, user: admin, name: "Parent")
      child = create(:folder, user: admin, parent: parent, name: "Child")
      editors = create(:user_group, name: "Editors")
      orphaned_group = create(:user_group, name: "Former Editors")
      create(:folder_policy, folder: parent, user_group: editors, read_access: true)
      orphaned_policy = create(:folder_policy, folder: parent, user_group: orphaned_group, modify_access: true)
      create(:folder_policy, folder: child, user_group: editors, manage_access: true)
      # A real dangling FK is prevented by the DB's foreign key constraint, so
      # simulate the "missing group" scenario (e.g. transient replication lag,
      # or a future soft-delete of groups) by stubbing the association away
      # on this one instance rather than mutating the DB directly.
      allow_any_instance_of(FolderPolicy).to receive(:user_group) do |policy|
        policy.id == orphaned_policy.id ? nil : UserGroup.find_by(id: policy.user_group_id)
      end

      get :folder_policies, params: { id: child.id }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("inherited_policies").map { |row| row["group_id"] }).not_to include(editors.id)
      orphaned_payload = response.parsed_body.fetch("inherited_policies").find { |row| row["id"] == orphaned_policy.id }
      expect(orphaned_payload).to include("group_name" => nil, "source_folder_name" => "Parent")
    end
  end

  # ===========================================================================
  # RENAME — PATCH #update permission enforcement + `can_modify` flag
  # ===========================================================================
  describe "PATCH #update (rename)" do
    let(:regular_user) { create(:user) }
    let(:group)         { create(:user_group) }

    it "allows an admin to rename a folder without any folder policy" do
      folder = create(:folder, user: admin, name: "Old Name")

      patch :update, params: { id: folder.id, folder: { name: "New Name" } }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq("New Name")
      expect(folder.reload.name).to eq("New Name")
    end

    it "denies rename for a regular user with no modify grant on the folder (403)" do
      folder = create(:folder, user: admin, name: "Old Name")

      sign_out admin
      sign_in regular_user
      request.env["devise.mapping"] = Devise.mappings[:user]

      patch :update, params: { id: folder.id, folder: { name: "New Name" } }, format: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to match(/modify/)
      expect(folder.reload.name).to eq("Old Name")
    end

    it "allows rename for a regular user with an explicit modify grant on the folder" do
      folder = create(:folder, user: admin, name: "Old Name")
      create(:folder_policy, :full_access, folder: folder, user_group: group)
      regular_user.user_groups << group

      sign_out admin
      sign_in regular_user
      request.env["devise.mapping"] = Devise.mappings[:user]

      patch :update, params: { id: folder.id, folder: { name: "New Name" } }, format: :json

      expect(response).to have_http_status(:ok)
      expect(folder.reload.name).to eq("New Name")
    end
  end

  # ===========================================================================
  # MOVE — PATCH #update with `parent_id` (delete-on-source + create-on-destination)
  # ===========================================================================
  describe "PATCH #update (move via parent_id)" do
    let(:regular_user) { create(:user) }
    let(:group)         { create(:user_group) }

    it "allows an admin to move a folder to a new parent" do
      origin      = create(:folder, user: admin, name: "Origin")
      destination = create(:folder, user: admin, name: "Destination")
      folder      = create(:folder, user: admin, parent: origin, name: "Movable")

      patch :update, params: { id: folder.id, folder: { parent_id: destination.id } }, format: :json

      expect(response).to have_http_status(:ok)
      expect(folder.reload.parent_id).to eq(destination.id)
    end

    it "allows moving a folder to root via parent_id: 'root'" do
      origin = create(:folder, user: admin, name: "Origin")
      folder = create(:folder, user: admin, parent: origin, name: "Movable")

      patch :update, params: { id: folder.id, folder: { parent_id: "root" } }, format: :json

      expect(response).to have_http_status(:ok)
      expect(folder.reload.parent_id).to be_nil
    end

    it "rejects moving a folder into itself or its own descendant (cycle)" do
      parent = create(:folder, user: admin, name: "Parent")
      child  = create(:folder, user: admin, parent: parent, name: "Child")

      patch :update, params: { id: parent.id, folder: { parent_id: child.id } }, format: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to match(/itself|subfolder/)
      expect(parent.reload.parent_id).to be_nil
    end

    it "returns 404 when the destination folder does not exist" do
      folder = create(:folder, user: admin, name: "Movable")

      patch :update, params: { id: folder.id, folder: { parent_id: 999_999 } }, format: :json

      expect(response).to have_http_status(:not_found)
    end

    it "denies the move for a regular user lacking :delete on the source folder" do
      origin      = create(:folder, user: admin, name: "Origin")
      destination = create(:folder, user: admin, name: "Destination")
      folder      = create(:folder, user: admin, parent: origin, name: "Movable")
      create(:folder_policy, folder: origin, user_group: group, read_access: true, modify_access: true) # no delete
      create(:folder_policy, :full_access, folder: destination, user_group: group)
      create(:folder_policy, :full_access, folder: folder, user_group: group) # so :modify on folder itself passes
      regular_user.user_groups << group

      sign_out admin
      sign_in regular_user
      request.env["devise.mapping"] = Devise.mappings[:user]

      patch :update, params: { id: folder.id, folder: { parent_id: destination.id } }, format: :json

      expect(response).to have_http_status(:forbidden)
      expect(folder.reload.parent_id).to eq(origin.id)
    end

    it "denies the move for a regular user lacking :create on the destination folder" do
      origin      = create(:folder, user: admin, name: "Origin")
      destination = create(:folder, user: admin, name: "Destination")
      folder      = create(:folder, user: admin, parent: origin, name: "Movable")
      create(:folder_policy, :full_access, folder: origin, user_group: group)
      create(:folder_policy, folder: destination, user_group: group, read_access: true) # no create
      create(:folder_policy, :full_access, folder: folder, user_group: group)
      regular_user.user_groups << group

      sign_out admin
      sign_in regular_user
      request.env["devise.mapping"] = Devise.mappings[:user]

      patch :update, params: { id: folder.id, folder: { parent_id: destination.id } }, format: :json

      expect(response).to have_http_status(:forbidden)
      expect(folder.reload.parent_id).to eq(origin.id)
    end

    it "allows the move for a regular user with :delete on source and :create on destination" do
      origin      = create(:folder, user: admin, name: "Origin")
      destination = create(:folder, user: admin, name: "Destination")
      folder      = create(:folder, user: admin, parent: origin, name: "Movable")
      create(:folder_policy, :full_access, folder: origin, user_group: group)
      create(:folder_policy, :full_access, folder: destination, user_group: group)
      create(:folder_policy, :full_access, folder: folder, user_group: group)
      regular_user.user_groups << group

      sign_out admin
      sign_in regular_user
      request.env["devise.mapping"] = Devise.mappings[:user]

      patch :update, params: { id: folder.id, folder: { parent_id: destination.id } }, format: :json

      expect(response).to have_http_status(:ok)
      expect(folder.reload.parent_id).to eq(destination.id)
    end
  end

  # ===========================================================================
  # GET #show — `can_modify` flag surfaced for folders and assets
  # ===========================================================================
  describe "GET #show (can_modify flag)" do
    let(:regular_user) { create(:user) }
    let(:group)         { create(:user_group) }

    it "marks every folder/asset can_modify: true for an admin" do
      parent = create(:folder, user: admin, name: "Parent")
      create(:folder, user: admin, parent: parent, name: "Child")
      create(:asset, user: admin, folder: parent, title: "Doc")

      get :show, params: { id: parent.id }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["folders"]).to all(include("can_modify" => true))
      expect(response.parsed_body["assets"]).to all(include("can_modify" => true))
    end

    it "marks can_modify: false for a regular user without a modify grant on the current folder" do
      parent = create(:folder, user: admin, name: "Parent")
      create(:folder, user: admin, parent: parent, name: "Child")
      create(:asset, user: admin, folder: parent, title: "Doc")
      create(:folder_policy, folder: parent, user_group: group, read_access: true) # read-only, no modify

      sign_out admin
      sign_in regular_user
      request.env["devise.mapping"] = Devise.mappings[:user]
      regular_user.user_groups << group

      get :show, params: { id: parent.id }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["folders"]).to all(include("can_modify" => false))
      expect(response.parsed_body["assets"]).to all(include("can_modify" => false))
    end

    it "marks can_modify: true for a regular user with an explicit modify grant" do
      # Note: `permissions_for` checks the policy on the exact folder only
      # (no ancestor walk) — a grant on `parent` does not automatically
      # cascade to `child`'s own `can_modify`, only to items that live
      # directly inside `parent` (assets + the folder-rename check for
      # `parent` itself). Grant on both so this covers both cases.
      parent = create(:folder, user: admin, name: "Parent")
      child = create(:folder, user: admin, parent: parent, name: "Child")
      create(:asset, user: admin, folder: parent, title: "Doc")
      create(:folder_policy, :full_access, folder: parent, user_group: group)
      create(:folder_policy, :full_access, folder: child, user_group: group)

      sign_out admin
      sign_in regular_user
      request.env["devise.mapping"] = Devise.mappings[:user]
      regular_user.user_groups << group

      get :show, params: { id: parent.id }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["folders"]).to all(include("can_modify" => true))
      expect(response.parsed_body["assets"]).to all(include("can_modify" => true))
    end

    it "marks root-level items (no parent folder) can_modify: true for any signed-in user" do
      create(:asset, user: admin, folder: nil, title: "Root Doc")

      sign_out admin
      sign_in regular_user
      request.env["devise.mapping"] = Devise.mappings[:user]

      get :show, params: { id: "root" }, format: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["assets"]).to all(include("can_modify" => true))
    end
  end
end
