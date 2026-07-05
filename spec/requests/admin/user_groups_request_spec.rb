require "rails_helper"

RSpec.describe "Admin::UserGroups coverage", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:super_admin) { create(:user, :super_admin) }
  let(:user) { create(:user) }
  let(:group) { create(:user_group, name: "Editors") }

  describe "authentication" do
    it "redirects signed-out users" do
      get "/admin/user_groups.json", as: :json
      expect(response).to redirect_to(new_user_session_path(format: :json))
    end

    it "renders the HTML shell and highlights the User Groups sidebar item" do
      sign_in admin

      get "/admin/user_groups"

      expect(response).to have_http_status(:ok)
      expect(assigns(:active_view)).to eq("User Groups")
      expect(response.body).to include('data-active-view="User Groups"')
    end

    it "forbids non-admin users" do
      sign_in user
      get "/admin/user_groups.json", as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "collection and records" do
    before { sign_in admin }

    it "lists groups with member counts and hierarchy metadata" do
      group.users << user

      get "/admin/user_groups.json", as: :json

      expect(response).to have_http_status(:ok)
      entry = response.parsed_body["user_groups"].find { |row| row["id"] == group.id }
      expect(entry).to include("name" => "Editors", "member_count" => 1)
    end

    it "keeps parent_id nil when no parent closure exists" do
      group
      get "/admin/user_groups.json", as: :json

      expect(response.parsed_body["user_groups"]).to include(include("parent_id" => nil))
    end

    it "creates a child group under a parent" do
      parent = group

      expect do
        post "/admin/user_groups.json", params: {
          user_group: { name: "Designers", description: "Design team" }, parent_id: parent.id
        }, as: :json
      end.to change(UserGroup, :count).by(1)

      expect(response).to have_http_status(:created)
      child = UserGroup.find_by!(name: "Designers")
      expect(child.parent_id).to eq(parent.id)
    end

    it "returns validation errors on create" do
      post "/admin/user_groups.json", params: { user_group: { name: "" } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to include(a_string_matching(/Name/))
    end

    it "creates a group without nesting when the parent cannot be found" do
      post "/admin/user_groups.json", params: { user_group: { name: "Orphans" }, parent_id: 0 }, as: :json

      expect(response).to have_http_status(:created)
      expect(UserGroup.find_by!(name: "Orphans").parent_id).to be_nil
    end

    it "shows members and direct child groups" do
      child = create(:user_group, name: "Nested")
      group.users << user
      group.add_child(child)

      get "/admin/user_groups/#{group.id}.json", as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body["group"]
      expect(body["members"].map { |member| member["email"] }).to include(user.email)
      expect(body["child_groups"].map { |row| row["name"] }).to include("Nested")
    end

    it "returns not found for missing groups" do
      get "/admin/user_groups/0.json", as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "updates regular groups" do
      patch "/admin/user_groups/#{group.id}.json", params: { user_group: { name: "Editors Updated", description: "Updated" } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(group.reload).to have_attributes(name: "Editors Updated", description: "Updated")
    end

    it "returns update validation errors" do
      other = create(:user_group, name: "Other")
      patch "/admin/user_groups/#{group.id}.json", params: { user_group: { name: other.name } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["success"]).to be(false)
    end

    it "forbids regular admins from editing the administrators system group" do
      administrators = create(:user_group, :administrators)
      patch "/admin/user_groups/#{administrators.id}.json", params: { user_group: { description: "Admins" } }, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "allows super admins to edit administrators group metadata" do
      sign_out admin
      sign_in super_admin
      administrators = create(:user_group, :administrators)

      patch "/admin/user_groups/#{administrators.id}.json", params: { user_group: { description: "Core admins" } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(administrators.reload.description).to eq("Core admins")
    end

    it "deletes regular groups and rejects system groups" do
      doomed = create(:user_group)
      delete "/admin/user_groups/#{doomed.id}.json", as: :json
      expect(response).to have_http_status(:ok)
      expect(UserGroup.exists?(doomed.id)).to be(false)

      everyone = create(:user_group, :everyone)
      delete "/admin/user_groups/#{everyone.id}.json", as: :json
      expect(response).to have_http_status(:forbidden)
      expect(UserGroup.exists?(everyone.id)).to be(true)
    end
  end

  describe "member management" do
    before { sign_in admin }

    it "adds members by email and legacy alias, then removes by id" do
      post "/admin/user_groups/#{group.id}/add_member.json", params: { email: user.email }, as: :json
      expect(response).to have_http_status(:ok)
      expect(group.users).to include(user)

      another = create(:user)
      post "/admin/user_groups/#{group.id}/add_user.json", params: { user_id: another.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(group.reload.users).to include(another)

      delete "/admin/user_groups/#{group.id}/remove_member.json", params: { user_id: user.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(group.reload.users).not_to include(user)
    end

    it "returns member-management edge errors" do
      everyone = create(:user_group, :everyone)
      administrators = create(:user_group, :administrators)
      super_group = create(:user_group, :super_administrators)

      post "/admin/user_groups/#{group.id}/add_member.json", params: { email: "missing@example.com" }, as: :json
      expect(response).to have_http_status(:not_found)

      post "/admin/user_groups/#{everyone.id}/add_member.json", params: { user_id: user.id }, as: :json
      expect(response).to have_http_status(:forbidden)

      post "/admin/user_groups/#{super_group.id}/add_member.json", params: { user_id: user.id }, as: :json
      expect(response).to have_http_status(:forbidden)

      post "/admin/user_groups/#{administrators.id}/add_member.json", params: { user_id: admin.id }, as: :json
      expect(response).to have_http_status(:forbidden)

      delete "/admin/user_groups/#{everyone.id}/remove_member.json", params: { user_id: user.id }, as: :json
      expect(response).to have_http_status(:forbidden)

      delete "/admin/user_groups/#{administrators.id}/remove_member.json", params: { user_id: user.id }, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "does not duplicate existing group members" do
      group.users << user

      expect do
        post "/admin/user_groups/#{group.id}/add_member.json", params: { user_id: user.id }, as: :json
      end.not_to change { group.reload.users.count }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "sub-group membership" do
    before { sign_in admin }

    it "adds and removes child groups" do
      child = create(:user_group, name: "Child")
      post "/admin/user_groups/#{group.id}/add_group_member.json", params: { child_group_id: child.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(child.reload.parent_id).to eq(group.id)

      delete "/admin/user_groups/#{group.id}/remove_group_member.json", params: { child_group_id: child.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(child.reload.parent_id).to be_nil
    end

    it "handles missing and invalid child groups" do
      post "/admin/user_groups/#{group.id}/add_group_member.json", params: { child_group_id: 0 }, as: :json
      expect(response).to have_http_status(:not_found)

      post "/admin/user_groups/#{group.id}/add_group_member.json", params: { child_group_id: group.id }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      delete "/admin/user_groups/#{group.id}/remove_group_member.json", params: { child_group_id: 0 }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
    end

    it "keeps the other parent link untouched when removing an unrelated child" do
      other_parent = create(:user_group, name: "Other Parent")
      child = create(:user_group, name: "Nested Elsewhere")
      other_parent.add_child(child)

      delete "/admin/user_groups/#{group.id}/remove_group_member.json", params: { child_group_id: child.id }, as: :json

      expect(response).to have_http_status(:ok)
      expect(child.reload.parent_id).to eq(other_parent.id)
    end
  end
end
