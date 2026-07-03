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
        get "folders/:id/profiles" => "folders#profiles"
        post "folders/:id/purge_cdn" => "folders#purge_folder_cdn"
        get "folders/:id/schema" => "folders#schema"
        post "folders/:id/policies" => "folders#upsert_folder_policy"
        delete "folders/:id/policies/:group_id" => "folders#remove_folder_policy"
      end
    end

    request.env["devise.mapping"] = Devise.mappings[:user]
    sign_in admin
    allow(controller).to receive(:authenticate_hybrid!).and_return(true)
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
end
