require "rails_helper"

RSpec.describe "Admin::SystemConfigurations", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  describe "GET /admin/system_configurations/logging" do
    it "redirects unauthenticated users to sign in" do
      get admin_system_configurations_logging_path, as: :json

      expect(response).to redirect_to(new_user_session_path(format: :json))
    end

    it "returns forbidden for non-admin users" do
      sign_in user

      get admin_system_configurations_logging_path, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "returns default data when no configuration exists" do
      sign_in admin

      get admin_system_configurations_logging_path, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "success" => true,
        "current_level" => "INFO",
        "fallback_level" => "INFO",
        "ttl_active" => false,
      )
    end
  end

  describe "POST /admin/system_configurations/logging" do
    it "updates the logging level for admins" do
      sign_in admin

      post admin_system_configurations_logging_path,
           params: { level: "warn", ttl_minutes: 10 },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)

      config = SystemConfiguration.find_by!(key: "global_log_level")
      expect(config.value).to eq("WARN")
      expect(config.updated_by_id).to eq(admin.id)
      expect(config.expires_at).to be_present
    end

    it "rejects invalid log levels" do
      sign_in admin

      post admin_system_configurations_logging_path,
           params: { level: "verbose" },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("success" => false, "error" => "Invalid log level provided.")
    end
  end
end
