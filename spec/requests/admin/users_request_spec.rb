require "rails_helper"

RSpec.describe "Admin::Users coverage", type: :request do
  let(:admin) { create(:user, :admin, first_name: "Ada", last_name: "Admin", department: "Ops") }
  let(:user) { create(:user, first_name: "Bob", last_name: "Builder", department: "Marketing") }

  before do
    allow(EmailOrchestrator).to receive(:trigger)
    allow(AuditLog).to receive(:record)
  end

  describe "authentication and listing" do
    it "redirects signed-out users" do
      get "/admin/users.json", as: :json
      expect(response).to redirect_to(new_user_session_path(format: :json))
    end

    it "forbids non-admin users" do
      sign_in user
      get "/admin/users.json", as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "renders the HTML shell and highlights the Users sidebar item" do
      sign_in admin

      get "/admin/users"

      expect(response).to have_http_status(:ok)
      expect(assigns(:active_view)).to eq("Users")
      expect(response.body).to include('data-active-view="Users"')
    end

    it "returns users filtered by search" do
      sign_in admin
      user

      get "/admin/users.json", params: { search: "market" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["users"].map { |entry| entry["email"] }).to include(user.email)
      expect(response.parsed_body["users"].map { |entry| entry["email"] }).not_to include(admin.email)
    end

    it "returns all users when no search filter is provided" do
      sign_in admin
      user

      get "/admin/users.json", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["users"].map { |entry| entry["email"] }).to include(user.email, admin.email)
    end
  end

  describe "CRUD" do
    before { sign_in admin }

    it "shows a detailed user with impersonators" do
      actor = create(:user, first_name: "Ima", last_name: "Poster")
      user.grant_impersonation_to(actor)

      get "/admin/users/#{user.id}.json", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("user", "impersonators")).to include(
        a_hash_including("id" => actor.id, "email" => actor.email)
      )
      expect(response.parsed_body.dig("user", "preferences")).to include("language")
    end

    it "includes a super_admin flag distinct from admin so clients can hide " \
       "impersonation/config controls for super-admin targets" do
      super_admin_user = create(:user, :super_admin)

      get "/admin/users/#{super_admin_user.id}.json", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("user", "super_admin")).to be(true)

      get "/admin/users/#{user.id}.json", as: :json
      expect(response.parsed_body.dig("user", "super_admin")).to be(false)
    end

    it "returns 404 for missing users" do
      get "/admin/users/0.json", as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("User not found.")
    end

    it "shows an empty preferences hash when the user has no preference record" do
      user.preference&.destroy!

      get "/admin/users/#{user.id}.json", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("user", "preferences")).to eq({})
    end

    it "creates a user and triggers the welcome email" do
      expect do
        post "/admin/users.json", params: {
          user: { email: "new.user@example.com", first_name: "New", last_name: "User", department: "Design", role: "viewer" },
        }, as: :json
      end.to change(User, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(EmailOrchestrator).to have_received(:trigger).with("user_created", "new.user@example.com", hash_including("user"))
    end

    it "returns validation errors on create" do
      post "/admin/users.json", params: { user: { email: "", first_name: "No", last_name: "Email" } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to include(a_string_matching(/Email/))
    end

    it "updates a local user including explicit admin flag" do
      patch "/admin/users/#{user.id}.json", params: { user: { department: "Legal", admin: true } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(user.reload).to have_attributes(department: "Legal", admin: true)
    end

    it "prevents an admin from changing their own admin flag" do
      patch "/admin/users/#{admin.id}.json", params: { user: { admin: "0" } }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["errors"]).to include("You cannot change your own admin status")
    end

    it "does not change SSO-owned profile fields" do
      sso_user = create(:user, :sso, first_name: "Original", last_name: "Name", email: "sso@example.com")
      patch "/admin/users/#{sso_user.id}.json", params: {
        user: { email: "changed@example.com", first_name: "Changed", last_name: "Person", department: "IT" },
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(sso_user.reload).to have_attributes(email: "sso@example.com", first_name: "Original", last_name: "Name", department: "IT")
    end

    it "forbids super-admin group members without the admin flag from changing admin status" do
      delegated_super_admin = create(:user, admin: false, role: "viewer")
      delegated_super_admin.user_groups << create(:user_group, :super_administrators)

      sign_in delegated_super_admin

      patch "/admin/users/#{user.id}.json", params: { user: { admin: true } }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["errors"]).to include("Unauthorized to modify admin status")
    end

    it "returns update validation errors" do
      patch "/admin/users/#{user.id}.json", params: { user: { email: admin.email } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["success"]).to be(false)
    end

    it "forbids deleting your own account" do
      delete "/admin/users/#{admin.id}.json", as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "deactivates another account" do
      delete "/admin/users/#{user.id}.json", as: :json
      expect(response).to have_http_status(:ok)
      expect(user.reload.active).to be(false)
    end
  end

  describe "status and passwords" do
    before { sign_in admin }

    it "toggles active users inactive and inactive users active" do
      post "/admin/users/#{user.id}/toggle_status.json", as: :json
      expect(response.parsed_body["active"]).to be(false)
      post "/admin/users/#{user.id}/toggle_status.json", as: :json
      expect(response.parsed_body["active"]).to be(true)
    end

    it "forbids suspending your own (currently signed-in) account" do
      post "/admin/users/#{admin.id}/toggle_status.json", as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("You cannot suspend your own account.")
      expect(admin.reload.active).to be(true)
    end

    it "changes passwords for local users" do
      post "/admin/users/#{user.id}/change_password.json", params: {
        new_password: "newpassword123", new_password_confirmation: "newpassword123", force_change: "1"
      }, as: :json
      expect(response).to have_http_status(:ok)
      expect(user.reload.force_password_change).to be(true)
    end

    it "rejects password changes for SSO users" do
      sso_user = create(:user, :sso)
      post "/admin/users/#{sso_user.id}/change_password.json", params: { new_password: "newpassword123" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("SSO")
    end

    it "returns password validation errors" do
      post "/admin/users/#{user.id}/change_password.json", params: { new_password: "short", new_password_confirmation: "different" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  describe "groups" do
    let(:group) { create(:user_group, name: "Editors") }
    let(:everyone) { create(:user_group, :everyone) }
    let(:administrators) { create(:user_group, :administrators) }
    let(:super_group) { create(:user_group, :super_administrators) }

    before { sign_in admin }

    it "lists current and assignable groups excluding everyone" do
      group.users << user
      everyone

      get "/admin/users/#{user.id}/groups.json", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["groups"].map { |entry| entry["name"] }).to include("Editors")
      expect(response.parsed_body["all_groups"].map { |entry| entry["slug"] }).not_to include("everyone")
    end

    it "adds and removes regular groups" do
      post "/admin/users/#{user.id}/add_group.json", params: { group_id: group.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(group.users).to include(user)

      delete "/admin/users/#{user.id}/remove_group/#{group.id}.json", as: :json
      expect(response).to have_http_status(:ok)
      expect(group.reload.users).not_to include(user)
    end

    it "returns not found and protected group errors" do
      post "/admin/users/#{user.id}/add_group.json", params: { group_id: 0 }, as: :json
      expect(response).to have_http_status(:not_found)

      post "/admin/users/#{user.id}/add_group.json", params: { group_id: everyone.id }, as: :json
      expect(response).to have_http_status(:forbidden)

      post "/admin/users/#{user.id}/add_group.json", params: { group_id: super_group.id }, as: :json
      expect(response).to have_http_status(:forbidden)

      delete "/admin/users/#{user.id}/remove_group/#{administrators.id}.json", as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids modifying protected groups on yourself" do
      admin.user_groups << administrators

      post "/admin/users/#{admin.id}/add_group.json", params: { group_id: administrators.id }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("You cannot add yourself")

      delete "/admin/users/#{admin.id}/remove_group/#{everyone.id}.json", as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("Cannot remove users from 'everyone'.")
    end

    it "returns not found when removing an unknown group" do
      delete "/admin/users/#{user.id}/remove_group/0.json", as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("Group not found.")
    end

    it "returns validation errors when adding a group fails" do
      group_users = double("group users", include?: false)
      allow(group_users).to receive(:<<).and_raise(ActiveRecord::RecordInvalid.new(group))
      failing_group = instance_double(
        UserGroup,
        everyone?: false,
        super_administrators?: false,
        administrators?: false,
        users: group_users,
        name: group.name
      )
      allow(UserGroup).to receive(:find_by).and_return(failing_group)

      post "/admin/users/#{user.id}/add_group.json", params: { group_id: group.id }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  describe "impersonation" do
    before { sign_in admin }

    it "lists, grants, revokes, and starts impersonation" do
      actor = create(:user, first_name: "Ivy")
      user.grant_impersonation_to(actor)

      get "/admin/users/#{user.id}/impersonators.json", params: { search: actor.email }, as: :json
      expect(response.parsed_body["impersonators"].map { |entry| entry["email"] }).to include(actor.email)

      new_actor = create(:user)
      post "/admin/users/#{user.id}/impersonators.json", params: { impersonator_id: new_actor.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(user.impersonators.reload).to include(new_actor)

      delete "/admin/users/#{user.id}/impersonators/#{new_actor.id}.json", as: :json
      expect(response).to have_http_status(:ok)
      expect(user.impersonators.reload).not_to include(new_actor)

      post "/admin/users/#{user.id}/start_impersonation.json", as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["redirect_to"]).to eq("/dashboard")
    end

    it "handles missing impersonators and forbidden targets" do
      post "/admin/users/#{user.id}/impersonators.json", params: { impersonator_id: 0 }, as: :json
      expect(response).to have_http_status(:not_found)

      super_admin = create(:user, :super_admin)
      post "/admin/users/#{super_admin.id}/impersonators.json", params: { impersonator_id: user.id }, as: :json
      expect(response).to have_http_status(:forbidden)

      post "/admin/users/#{admin.id}/start_impersonation.json", as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "lists impersonators without a search filter and tolerates missing revoke targets" do
      actor = create(:user, first_name: "Ivy")
      user.grant_impersonation_to(actor)

      get "/admin/users/#{user.id}/impersonators.json", as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["impersonators"].map { |entry| entry["email"] }).to include(actor.email)

      delete "/admin/users/#{user.id}/impersonators/0.json", as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(AuditLog).to have_received(:record).with(hash_including(changes_data: hash_including(revoked_from: nil)))
    end

    it "returns validation errors when granting impersonation fails" do
      actor = create(:user)
      allow_any_instance_of(User).to receive(:grant_impersonation_to).and_raise(ActiveRecord::RecordInvalid.new(user))

      post "/admin/users/#{user.id}/impersonators.json", params: { impersonator_id: actor.id }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  describe "preferences" do
    before { sign_in admin }

    it "shows and updates preferences" do
      get "/admin/users/#{user.id}/preferences.json", as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["preferences"]).to include("language")

      patch "/admin/users/#{user.id}/preferences.json", params: { preferences: { language: "de", receive_mention_emails: false } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(user.preference.reload.language).to eq("de")
      expect(user.preference.receive_mention_emails).to be(false)
    end

    it "returns validation errors for unsupported languages" do
      patch "/admin/users/#{user.id}/preferences.json", params: { preferences: { language: "xx" } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to be_present
    end
  end
end
