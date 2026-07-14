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

    it "returns persisted configuration data and remaining minutes for active TTLs" do
      sign_in admin
      config = SystemConfiguration.create!(
        key: "global_log_level",
        data_type: "string",
        value: "ERROR",
        fallback_value: "WARN",
        expires_at: 10.minutes.from_now
      )

      get admin_system_configurations_logging_path, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "current_level" => config.value,
        "fallback_level" => config.fallback_value,
        "ttl_active" => true
      )
      expect(response.parsed_body["minutes_remaining"]).to be > 0
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

    it "clears TTL state when no ttl_minutes are provided" do
      sign_in admin
      SystemConfiguration.create!(
        key: "global_log_level",
        data_type: "string",
        value: "INFO",
        fallback_value: "DEBUG",
        expires_at: 5.minutes.from_now
      )

      post admin_system_configurations_logging_path,
           params: { level: "error", ttl_minutes: 0 },
           as: :json

      expect(response).to have_http_status(:ok)
      config = SystemConfiguration.find_by!(key: "global_log_level")
      expect(config.value).to eq("ERROR")
      expect(config.expires_at).to be_nil
      expect(config.fallback_value).to be_nil
    end

    it "accepts TRACE (the maximum-verbosity level the frontend offers, previously missing from the backend allow-list)" do
      sign_in admin

      post admin_system_configurations_logging_path,
           params: { level: "trace", ttl_minutes: 15 },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)

      config = SystemConfiguration.find_by!(key: "global_log_level")
      expect(config.value).to eq("TRACE")
    end

    it "allows nil updated_by_id when current_user is unavailable after admin authorization" do
      sign_in admin
      allow_any_instance_of(Admin::SystemConfigurationsController).to receive(:current_user_admin?).and_return(true) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Admin::SystemConfigurationsController).to receive(:current_user).and_return(nil) # rubocop:disable RSpec/AnyInstance

      post admin_system_configurations_logging_path,
           params: { level: "info", ttl_minutes: 1 },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(SystemConfiguration.find_by!(key: "global_log_level").updated_by_id).to be_nil
    end

    it "rejects invalid log levels" do
      sign_in admin

      post admin_system_configurations_logging_path,
           params: { level: "verbose" },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("success" => false, "error" => "Invalid log level provided.")
    end

    it "returns validation errors when the configuration update fails" do
      sign_in admin
      errors = instance_double(ActiveModel::Errors, full_messages: [ "Value is invalid" ])
      allow_any_instance_of(SystemConfiguration).to receive(:update).and_return(false) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(SystemConfiguration).to receive(:errors).and_return(errors) # rubocop:disable RSpec/AnyInstance

      post admin_system_configurations_logging_path,
           params: { level: "warn", ttl_minutes: 5 },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("success" => false, "error" => "Value is invalid")
    end
  end
end
