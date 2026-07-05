require "rails_helper"

RSpec.describe "Settings coverage", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  before do
    allow(StorageManager).to receive(:reset_active_adapter!)
  end

  describe "GET /settings" do
    it "redirects signed-out users" do
      get "/settings"
      expect(response).to redirect_to(new_user_session_path)
    end

    it "renders general settings for regular users" do
      sign_in user
      allow(Setting).to receive(:get).and_call_original
      allow(Setting).to receive(:get).with("active_storage_provider").and_return("local")
      allow(Setting).to receive(:get_provider_config).with("local").and_return({})

      get "/settings"

      expect(response).to have_http_status(:ok)
      expect(assigns(:active_view)).to eq("General")
      expect(response.body).to include('data-active-view="General"')
    end

    it "renders system settings for admins and masks secrets" do
      sign_in admin
      allow(Setting).to receive(:get).and_call_original
      allow(Setting).to receive(:get).with("smtp_settings").and_return("password" => "secret")
      allow(Setting).to receive(:get).with("active_storage_provider").and_return("aws")
      allow(Setting).to receive(:get).with("storage_config_aws").and_return({ "secret_key" => "secret", "bucket" => "assets" })
      allow(Setting).to receive(:get).with(/storage_config_/).and_return({})
      allow(Setting).to receive(:get_provider_config).with("aws").and_return("secret_key" => "********")

      get "/settings/system"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("********")
      expect(response.body).not_to include("secret_key&quot;:&quot;secret")
      expect(assigns(:active_view)).to eq("System Ops")
      expect(response.body).to include('data-active-view="System Ops"')
    end

    it "ignores malformed stored provider JSON" do
      sign_in admin
      allow(Setting).to receive(:get).and_call_original
      allow(Setting).to receive(:get).with("active_storage_provider").and_return("local")
      allow(Setting).to receive(:get).with("storage_config_aws").and_return("{not-json")
      allow(Setting).to receive(:get_provider_config).with("local").and_return({})

      get "/settings/system"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("System")
    end

    it "redirects regular users away from system settings" do
      sign_in user

      get "/settings/system"

      expect(response).to redirect_to(settings_path)
    end

    it "masks only populated secret-like provider settings" do
      sign_in admin
      Setting.set("active_storage_provider", "aws")
      Setting.set("storage_config_aws", {
        "secret_key" => "top-secret",
        "bucket" => "assets",
        "access_key" => "",
      }.to_json)

      get "/settings/system"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("********")
      expect(response.body).to include("assets")
      expect(response.body).not_to include("top-secret")
    end
  end

  describe "PATCH /settings" do
    it "persists only user-safe keys for regular users" do
      sign_in user
      allow(Setting).to receive(:set)

      patch "/settings", params: { settings: { notifications_enabled: "1", theme_preference: "dark", site_name: "Nope" } }

      expect(response).to redirect_to(settings_path)
      expect(Setting).to have_received(:set).with("notifications_enabled", "1")
      expect(Setting).to have_received(:set).with("theme_preference", "dark")
      expect(Setting).not_to have_received(:set).with("site_name", anything)
    end

    it "allows admins to persist administrative keys" do
      sign_in admin
      allow(Setting).to receive(:set)

      patch "/settings", params: { settings: { site_name: "Capri", max_file_size: "42", allowed_mimes: "image/png", keycloak_realm: "dam" } }

      expect(response).to redirect_to(settings_path)
      expect(Setting).to have_received(:set).with("site_name", "Capri")
      expect(Setting).to have_received(:set).with("keycloak_realm", "dam")
    end
  end

  describe "PATCH /settings/update_storage" do
    it "merges new values while preserving masked and blank existing secrets" do
      sign_in admin
      Setting.set("storage_config_aws", { "secret_key" => "real-secret", "bucket" => "old" }.to_json)

      patch "/settings/update_storage", params: {
        storage_config: { provider: "aws", secret_key: "********", bucket: "new", region: "" },
      }, as: :json

      expect(response).to have_http_status(:ok)
      stored = JSON.parse(Setting.get("storage_config_aws"))
      expect(stored).to include("secret_key" => "real-secret", "bucket" => "new")
      expect(Setting.get("active_storage_provider")).to eq("aws")
      expect(StorageBackend.find_by(provider_type: "aws")).to be_active
    end

    it "returns validation errors when persistence raises" do
      sign_in admin
      allow(Setting).to receive(:get).and_return({})
      allow(Setting).to receive(:set).and_raise(StandardError, "boom")

      patch "/settings/update_storage", params: { storage_config: { provider: "aws", bucket: "x" } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("boom")
    end

    it "continues when syncing the storage backend fails and existing config is not structured" do
      sign_in admin
      allow(Setting).to receive(:get).and_call_original
      allow(Setting).to receive(:get).with("storage_config_aws").and_return(123)
      allow(StorageBackend).to receive(:find_or_initialize_by).and_raise(StandardError, "sync failed")
      allow(Rails.logger).to receive(:warn)

      patch "/settings/update_storage", params: {
        storage_config: { provider: "aws", bucket: "new-bucket" },
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to include("AWS")
      expect(Rails.logger).to have_received(:warn).with(include("sync failed"))
    end
  end

  describe "POST /settings/test_connection" do
    it "tests local storage successfully" do
      sign_in admin
      adapter = instance_double(StorageAdapters::LocalStorageAdapter, test_connection: { success: true, message: "ok" })
      allow(StorageAdapters::LocalStorageAdapter).to receive(:new).with({}).and_return(adapter)

      post "/settings/test_connection", params: { storage_config: { provider: "local" } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("success" => true, "message" => "ok")
    end

    it "unmasks stored secrets and reports adapter failures" do
      sign_in admin
      Setting.set("storage_config_aws", { "secret_key" => "real-secret" }.to_json)
      adapter = instance_double(StorageAdapters::S3Adapter, test_connection: { success: false, error: "denied" })
      allow(StorageAdapters::S3Adapter).to receive(:new).with(hash_including("secret_key" => "real-secret")).and_return(adapter)

      post "/settings/test_connection", params: { storage_config: { provider: "aws", secret_key: "********" } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include("success" => false, "error" => "denied")
    end

    it "tests Google Cloud Storage adapters" do
      sign_in admin
      adapter = instance_double(StorageAdapters::GcsAdapter, test_connection: { success: true, message: "gcs ok" })
      allow(StorageAdapters::GcsAdapter).to receive(:new).with(hash_including("project_id" => "capri")).and_return(adapter)

      post "/settings/test_connection", params: {
        storage_config: { provider: "google", project_id: "capri", credentials_json: "{}" },
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("success" => true, "message" => "gcs ok")
    end

    it "tests Azure storage adapters" do
      sign_in admin
      adapter = instance_double(StorageAdapters::AzureAdapter, test_connection: { success: true, message: "azure ok" })
      allow(StorageAdapters::AzureAdapter).to receive(:new).with(hash_including("account_name" => "acct")).and_return(adapter)

      post "/settings/test_connection", params: {
        storage_config: { provider: "azure", account_name: "acct", account_key: "secret", container: "assets" },
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("success" => true, "message" => "azure ok")
    end

    it "returns adapter exceptions as validation errors" do
      sign_in admin
      allow(StorageAdapters::GcsAdapter).to receive(:new).and_raise(StandardError, "network down")

      post "/settings/test_connection", params: {
        storage_config: { provider: "google", project_id: "capri", credentials_json: "{}" },
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include("success" => false, "error" => "network down")
    end

    it "handles unknown providers" do
      sign_in admin

      post "/settings/test_connection", params: { storage_config: { provider: "bogus" } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("Unknown provider")
    end

    it "unmasks secrets from hash-backed provider settings" do
      sign_in admin
      allow(Setting).to receive(:get).and_call_original
      allow(Setting).to receive(:get).with("storage_config_aws").and_return({ "secret_key" => "hash-secret" })
      adapter = instance_double(StorageAdapters::S3Adapter, test_connection: { success: true, message: "ok" })
      allow(StorageAdapters::S3Adapter).to receive(:new).with(hash_including("secret_key" => "hash-secret")).and_return(adapter)

      post "/settings/test_connection", params: { storage_config: { provider: "aws", secret_key: "********" } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("success" => true, "message" => "ok")
    end
  end
end
