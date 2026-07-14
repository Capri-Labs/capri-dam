require "rails_helper"

RSpec.describe "Admin::Policies", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  describe "GET /admin/policies" do
    it "redirects unauthenticated users to sign in" do
      get admin_policies_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects non-admin users away with an access denied alert" do
      sign_in user

      get admin_policies_path

      expect(response).to redirect_to(authenticated_root_path)
      expect(flash[:alert]).to eq("Access Denied: Admins only.")
    end

    it "renders the Security Policies screen for admins" do
      sign_in admin

      get admin_policies_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-view="policies"')
    end

    it "marks the Security Policies nav item active for admins" do
      sign_in admin

      get admin_policies_path

      expect(response.body).to include('data-active-view="Security Policies"')
    end

    it "passes the current user's admin/super-admin flags to the mounted React root" do
      sign_in admin

      get admin_policies_path

      expect(response.body).to include("data-current-user-id=\"#{admin.id}\"")
      expect(response.body).to include('data-is-admin="true"')
    end
  end
end
