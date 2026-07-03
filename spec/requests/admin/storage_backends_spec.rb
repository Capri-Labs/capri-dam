require "rails_helper"

RSpec.describe "Admin::StorageBackends", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }
  let!(:backend) { create(:storage_backend, name: "Primary", provider_type: "local", active: true, configuration: { "api_key" => "secret1234" }) }
  let!(:secondary_backend) { create(:storage_backend, name: "Secondary", provider_type: "local", active: true) }

  describe "GET /admin/storage_backends" do
    it "redirects unauthenticated users" do
      get admin_storage_backends_path, as: :json

      expect(response).to redirect_to(new_user_session_path(format: :json))
    end

    it "redirects non-admin users away from the page" do
      sign_in user

      get admin_storage_backends_path, as: :json

      expect(response).to redirect_to(authenticated_root_path)
    end

    it "returns the backend list for admins" do
      sign_in admin

      get admin_storage_backends_path, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["storage_backends"].map { |item| item["name"] }).to include("Primary", "Secondary")
    end
  end

  describe "GET /admin/storage_backends/:id/edit" do
    it "returns the backend details for admins" do
      sign_in admin

      get edit_admin_storage_backend_path(backend), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("storage_backend", "configuration", "api_key")).to eq("********")
    end
  end

  describe "PATCH /admin/storage_backends/:id" do
    it "updates the backend and deactivates the others" do
      sign_in admin

      patch admin_storage_backend_path(backend),
            params: { storage_backend: { name: "Updated Primary", active: true } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(backend.reload.name).to eq("Updated Primary")
      expect(secondary_backend.reload.active).to be(false)
    end

    it "returns validation errors" do
      sign_in admin

      patch admin_storage_backend_path(backend),
            params: { storage_backend: { provider_type: "invalid" } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["errors"]).to include(a_string_matching(/Provider type is not included/))
    end

    it "does not deactivate the other backends when the updated backend remains inactive" do
      sign_in admin
      backend.update!(active: false)

      patch admin_storage_backend_path(backend),
            params: { storage_backend: { name: "Inactive", active: false } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(secondary_backend.reload.active).to be(true)
    end
  end
end
