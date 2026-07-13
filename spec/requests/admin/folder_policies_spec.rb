require "rails_helper"

RSpec.describe "Admin::FolderPolicies", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }
  let(:group) { create(:user_group, name: "Editors") }
  let(:parent_folder) { create(:folder, user: admin, name: "Parent") }
  let(:folder) { create(:folder, user: admin, parent: parent_folder, name: "Child") }
  let!(:parent_policy) { create(:folder_policy, :read_only, folder: parent_folder, user_group: group) }

  describe "GET /admin/folders/:folder_id/folder_policies" do
    it "redirects unauthenticated users to sign in" do
      get admin_folder_folder_policies_path(folder), as: :json

      expect(response).to redirect_to(new_user_session_path(format: :json))
    end

    it "returns forbidden for non-admin users" do
      sign_in user

      get admin_folder_folder_policies_path(folder), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "returns explicit and inherited policies for admins" do
      sign_in admin
      create(:folder_policy, :full_access, folder: folder, user_group: group)

      get admin_folder_folder_policies_path(folder), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["folder_name"]).to eq("Child")
      expect(response.parsed_body["explicit_policies"].first.dig("matrix", "manage")).to be(true)
      expect(response.parsed_body["inherited_policies"]).to be_empty
    end

    it "includes inherited policies when no explicit policy exists" do
      sign_in admin

      get admin_folder_folder_policies_path(folder), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["inherited_policies"].first["source_folder"]).to eq("Parent")
    end
  end

  describe "POST /admin/folders/:folder_id/folder_policies" do
    let(:params) do
      {
        group_id: group.id,
        policy: {
          read_access: true,
          modify_access: true,
          create_access: false,
          delete_access: false,
          replicate_access: false,
          manage_access: false,
          explicit_deny: false,
        },
      }
    end

    it "creates or updates a policy for admins" do
      sign_in admin

      expect do
        post admin_folder_folder_policies_path(folder), params: params, as: :json
      end.to change(FolderPolicy, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(response.parsed_body.dig("policy", "matrix", "modify")).to be(true)
    end

    it "enqueues a cascade job to descendant folders when cascade: true" do
      sign_in admin
      expect(PropagateAccessPolicyJob).to receive(:perform_later).once.with(
        folder_id:   folder.id,
        group_id:    group.id,
        permissions: hash_including("read_access" => true, "modify_access" => true),
        operation:   "upsert"
      )

      post admin_folder_folder_policies_path(folder), params: params.merge(cascade: true), as: :json

      expect(response).to have_http_status(:ok)
    end

    it "does not enqueue a cascade job by default" do
      sign_in admin
      expect(PropagateAccessPolicyJob).not_to receive(:perform_later)

      post admin_folder_folder_policies_path(folder), params: params, as: :json
    end

    it "returns validation errors" do
      sign_in admin
      errors = instance_double(ActiveModel::Errors, full_messages: [ "Invalid policy" ])
      allow_any_instance_of(FolderPolicy).to receive(:update).and_return(false)
      allow_any_instance_of(FolderPolicy).to receive(:errors).and_return(errors)

      post admin_folder_folder_policies_path(folder), params: params, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("success" => false, "errors" => [ "Invalid policy" ])
    end
  end

  describe "DELETE /admin/folders/:folder_id/folder_policies/:group_id" do
    let!(:policy) { create(:folder_policy, folder: folder, user_group: group) }

    it "removes a policy for admins" do
      sign_in admin

      expect do
        delete admin_folder_folder_policy_path(folder, group_id: group.id), as: :json
      end.to change(FolderPolicy, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
    end

    it "returns success when there is no explicit policy to remove" do
      sign_in admin
      policy.destroy!

      expect do
        delete admin_folder_folder_policy_path(folder, group_id: group.id), as: :json
      end.not_to change(FolderPolicy, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("success" => true, "message" => "Folder policy removed.")
    end
  end
end
