require "rails_helper"

# Tests for the inline group assignment endpoints on Admin::UsersController.
# These are separate from the UserGroups#add_member / #remove_member tests
# because they operate from the *user* context rather than the *group* context.

RSpec.describe "Admin::Users — Group Assignment", type: :request do
  let(:super_admin) { create(:user, :super_admin) }
  let(:admin)       { create(:user, :admin) }
  let(:regular)     { create(:user) }

  let!(:custom_group)       { create(:user_group, name: "Design Team") }
  let!(:admin_group)        do
    UserGroup.find_or_create_by!(slug: "administrators") { |g|
      g.name = "Administrators"; g.is_system = true
    }
  end
  let!(:super_admin_group)  do
    UserGroup.find_or_create_by!(slug: "super-administrators") { |g|
      g.name = "Super Administrators"; g.is_system = true
    }
  end

  # ── GET /admin/users/:id/groups.json ─────────────────────────────────────────

  describe "GET /admin/users/:id/groups.json" do
    before { sign_in admin }

    it "returns groups, all_groups, and total" do
      regular.user_groups << custom_group
      get groups_admin_user_path(regular), as: :json

      json = response.parsed_body
      expect(json["total"]).to eq(regular.user_groups.count)
      expect(json["groups"]).to be_an(Array)
      expect(json["all_groups"]).to be_an(Array)
      # all_groups excludes 'everyone'
      expect(json["all_groups"].map { |g| g["slug"] }).not_to include("everyone")
    end

    it "includes member_count in each group" do
      regular.user_groups << custom_group
      get groups_admin_user_path(regular), as: :json
      groups = response.parsed_body["groups"]
      expect(groups.first).to have_key("member_count")
    end
  end

  # ── POST /admin/users/:id/add_group ──────────────────────────────────────────

  describe "POST /admin/users/:id/add_group" do
    context "as admin" do
      before { sign_in admin }

      it "adds user to a custom group" do
        post add_group_admin_user_path(regular), params: { group_id: custom_group.id }, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["success"]).to be true
        expect(regular.reload.user_groups).to include(custom_group)
      end

      it "is idempotent — adding again does not raise" do
        regular.user_groups << custom_group
        post add_group_admin_user_path(regular), params: { group_id: custom_group.id }, as: :json
        expect(response).to have_http_status(:ok)
      end

      it "returns 403 when trying to add to super-administrators" do
        post add_group_admin_user_path(regular), params: { group_id: super_admin_group.id }, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it "returns 403 when trying to add user to everyone" do
        everyone = UserGroup.find_or_create_by!(slug: "everyone") { |g| g.name = "Everyone"; g.is_system = true }
        post add_group_admin_user_path(regular), params: { group_id: everyone.id }, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it "writes an audit log entry" do
        expect {
          post add_group_admin_user_path(regular), params: { group_id: custom_group.id }, as: :json
        }.to change { AuditLog.where(action: "group_add").count }.by(1)
      end
    end

    context "as super-admin" do
      before { sign_in super_admin }

      it "can add user to the administrators group" do
        post add_group_admin_user_path(regular), params: { group_id: admin_group.id }, as: :json
        expect(response).to have_http_status(:ok)
        expect(regular.reload.user_groups).to include(admin_group)
      end
    end

    context "as unauthenticated user" do
      it "returns 403 or redirect" do
        post add_group_admin_user_path(regular), params: { group_id: custom_group.id }, as: :json
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
      end
    end
  end

  # ── DELETE /admin/users/:id/remove_group/:group_id ────────────────────────────

  describe "DELETE /admin/users/:id/remove_group/:group_id" do
    before do
      regular.user_groups << custom_group
      sign_in admin
    end

    it "removes the user from the group" do
      delete remove_group_admin_user_path(regular, group_id: custom_group.id), as: :json
      expect(response).to have_http_status(:ok)
      expect(regular.reload.user_groups).not_to include(custom_group)
    end

    it "writes an audit log entry" do
      expect {
        delete remove_group_admin_user_path(regular, group_id: custom_group.id), as: :json
      }.to change { AuditLog.where(action: "group_remove").count }.by(1)
    end

    it "returns 403 when admin tries to remove from administrators" do
      regular.user_groups << admin_group
      delete remove_group_admin_user_path(regular, group_id: admin_group.id), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    context "as super-admin" do
      before { sign_out admin; sign_in super_admin }

      it "can remove from the administrators group" do
        regular.user_groups << admin_group
        delete remove_group_admin_user_path(regular, group_id: admin_group.id), as: :json
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
