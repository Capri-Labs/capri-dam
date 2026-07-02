# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authorization, type: :controller do
  controller(ActionController::Base) do
    include Authorization

    attr_writer :current_user

    def current_user
      @current_user
    end

    def admin_action
      require_admin!
      return if performed?

      render json: { ok: true }
    end

    def super_admin_action
      require_super_admin!
      return if performed?

      render json: { ok: true }
    end

    def write_scope_action
      require_write_scope!
      return if performed?

      render json: { ok: true }
    end

    def admin_scope_action
      require_admin_scope!
      return if performed?

      render json: { ok: true }
    end

    def folder_action
      folder = Folder.find(params[:folder_id])
      check_folder_permission!(folder, params[:permission].to_sym)
      return if performed?

      render json: { ok: true }
    end

    def asset_read_action
      check_asset_read!(Asset.find(params[:asset_id]))
      return if performed?

      render json: { ok: true }
    end

    def asset_modify_action
      check_asset_modify!(Asset.find(params[:asset_id]))
      return if performed?

      render json: { ok: true }
    end

    def asset_delete_action
      check_asset_delete!(Asset.find(params[:asset_id]))
      return if performed?

      render json: { ok: true }
    end
  end

  before do
    routes.draw do
      get "admin_action" => "anonymous#admin_action"
      get "super_admin_action" => "anonymous#super_admin_action"
      post "write_scope_action" => "anonymous#write_scope_action"
      post "admin_scope_action" => "anonymous#admin_scope_action"
      get "folder_action" => "anonymous#folder_action"
      get "asset_read_action" => "anonymous#asset_read_action"
      patch "asset_modify_action" => "anonymous#asset_modify_action"
      delete "asset_delete_action" => "anonymous#asset_delete_action"
    end
  end

  def user_double(admin: false, super_admin: false, permissions: {})
    instance_double(
      User,
      admin?: admin,
      super_admin?: super_admin,
      member_of_administrators?: false,
      permissions_for: permissions
    )
  end

  describe "role guards" do
    it "forbids non-admins and allows administrator-group members" do
      regular = user_double
      group_admin = user_double
      allow(group_admin).to receive(:member_of_administrators?).and_return(true)

      controller.current_user = regular
      get :admin_action
      expect(response).to have_http_status(:forbidden)

      controller.current_user = group_admin
      get :admin_action
      expect(response).to have_http_status(:ok)
    end

    it "forbids non-super-admins and allows super-admins" do
      controller.current_user = user_double(admin: true, super_admin: false)
      get :super_admin_action
      expect(response).to have_http_status(:forbidden)

      controller.current_user = user_double(super_admin: true)
      get :super_admin_action
      expect(response).to have_http_status(:ok)
    end

    it "treats missing users as non-admins" do
      controller.current_user = nil

      expect(controller.current_user_admin?).to be(false)
    end
  end

  describe "PAT scope guards" do
    let(:user) { create(:user) }

    it "allows session-authenticated requests without checking PAT scopes" do
      post :write_scope_action

      expect(response).to have_http_status(:ok)
    end

    it "rejects write operations for read-only PATs" do
      _token, raw = PersonalAccessToken.generate_for(user, name: "read", scopes: "read")

      request.headers["Authorization"] = "Bearer #{raw}"
      post :write_scope_action

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to include("'write' or 'admin'")
    end

    it "accepts write operations for write-scoped PATs" do
      _token, raw = PersonalAccessToken.generate_for(user, name: "write", scopes: "write")

      request.headers["Authorization"] = "Bearer #{raw}"
      post :write_scope_action

      expect(response).to have_http_status(:ok)
    end

    it "requires admin scope for admin-scoped PAT operations" do
      _token, raw = PersonalAccessToken.generate_for(user, name: "write", scopes: "write")

      request.headers["Authorization"] = "Bearer #{raw}"
      post :admin_scope_action

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to include("'admin'")
    end
  end

  describe "folder and asset permission guards" do
    let(:folder) { create(:folder) }
    let(:asset) { create(:asset, folder: folder) }

    it "allows nil root folders and admin users" do
      controller.current_user = user_double
      expect(controller.check_folder_permission!(nil, :read)).to be_nil

      controller.current_user = user_double(admin: true)
      get :folder_action, params: { folder_id: folder.id, permission: "manage" }
      expect(response).to have_http_status(:ok)
    end

    it "renders forbidden when the user lacks a folder permission" do
      controller.current_user = user_double(permissions: { read: true })

      get :folder_action, params: { folder_id: folder.id, permission: "delete" }

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to include("'delete' permission")
    end

    it "allows asset read checks for root-level assets" do
      root_asset = create(:asset, folder: nil)
      controller.current_user = user_double

      get :asset_read_action, params: { asset_id: root_asset.id }

      expect(response).to have_http_status(:ok)
    end

    it "checks read, modify, and delete permissions on an asset folder" do
      controller.current_user = user_double(permissions: { read: true, modify: true, delete: false })

      get :asset_read_action, params: { asset_id: asset.id }
      expect(response).to have_http_status(:ok)

      patch :asset_modify_action, params: { asset_id: asset.id }
      expect(response).to have_http_status(:ok)

      delete :asset_delete_action, params: { asset_id: asset.id }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
