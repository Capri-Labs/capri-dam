require "rails_helper"

RSpec.describe "Admin::SystemStatus", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  describe "GET /admin/system_status" do
    before do
      allow(Setting).to receive(:get).with("smtp_settings").and_return({ "sender_address" => "ops@example.com" })
      allow(Setting).to receive(:get).with("notification_rules").and_return({ "errors" => true })
      allow_any_instance_of(Admin::SystemStatusController).to receive(:diagnostic_report).and_return("status" => "healthy")
    end

    it "redirects unauthenticated users to sign in" do
      get admin_system_status_path, as: :json

      expect(response).to redirect_to(new_user_session_path(format: :json))
    end

    it "returns forbidden for non-admin users" do
      sign_in user

      get admin_system_status_path, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "returns the diagnostic report for admins" do
      sign_in admin

      get admin_system_status_path, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("status" => "healthy")
    end
  end

  describe "POST /admin/system_status/update_smtp" do
    let(:smtp_params) do
      {
        smtp_config: {
          enabled: "true",
          address: "smtp.example.com",
          port: "587",
          domain: "example.com",
          user_name: "mailer",
          password: "secret",
          authentication: "plain",
          enable_starttls_auto: "true",
          sender_address: "ops@example.com",
        },
      }
    end

    it "persists smtp settings and reapplies them" do
      sign_in admin
      allow(Setting).to receive(:set)
      allow(Setting).to receive(:apply_smtp_settings!)
      allow(SmtpConnectionValidator).to receive(:new).and_return(instance_double(SmtpConnectionValidator, call: SmtpConnectionValidator::Result.new(success: true)))

      post admin_system_status_update_smtp_path, params: smtp_params, as: :json

      expect(response).to have_http_status(:ok)
      expect(Setting).to have_received(:set).with("smtp_settings", hash_including("address" => "smtp.example.com"))
      expect(Setting).to have_received(:apply_smtp_settings!)
    end

    it "rejects invalid configuration without persisting or handshaking" do
      sign_in admin
      allow(Setting).to receive(:set)
      allow(SmtpConnectionValidator).to receive(:new)

      post admin_system_status_update_smtp_path, params: {
        smtp_config: smtp_params[:smtp_config].merge(address: ""),
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["success"]).to be(false)
      expect(Setting).not_to have_received(:set)
      expect(SmtpConnectionValidator).not_to have_received(:new)
    end

    it "rejects and does not persist settings that fail the SMTP handshake" do
      sign_in admin
      allow(Setting).to receive(:set)
      failure = SmtpConnectionValidator::Result.new(success: false, error_code: "SMTP_AUTHENTICATION_FAILED", message: "bad credentials")
      allow(SmtpConnectionValidator).to receive(:new).and_return(instance_double(SmtpConnectionValidator, call: failure))

      post admin_system_status_update_smtp_path, params: smtp_params, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["error_code"]).to eq("SMTP_AUTHENTICATION_FAILED")
      expect(Setting).not_to have_received(:set)
    end
  end

  describe "POST /admin/system_status/test_connection" do
    let(:smtp_params) do
      {
        smtp_config: {
          enabled: "true",
          address: "smtp.example.com",
          port: "587",
          domain: "example.com",
          user_name: "mailer",
          password: "secret",
          authentication: "plain",
          enable_starttls_auto: "true",
          sender_address: "ops@example.com",
        },
      }
    end

    it "returns success without persisting when the handshake succeeds" do
      sign_in admin
      allow(Setting).to receive(:set)
      allow(SmtpConnectionValidator).to receive(:new).and_return(instance_double(SmtpConnectionValidator, call: SmtpConnectionValidator::Result.new(success: true)))

      post admin_system_status_test_connection_path, params: smtp_params, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(Setting).not_to have_received(:set)
    end

    it "returns a structured error code when the handshake fails" do
      sign_in admin
      failure = SmtpConnectionValidator::Result.new(success: false, error_code: "CONNECTION_TIMEOUT", message: "timed out")
      allow(SmtpConnectionValidator).to receive(:new).and_return(instance_double(SmtpConnectionValidator, call: failure))

      post admin_system_status_test_connection_path, params: smtp_params, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["error_code"]).to eq("CONNECTION_TIMEOUT")
    end

    it "returns INVALID_CONFIGURATION without attempting a handshake when required fields are missing" do
      sign_in admin
      allow(SmtpConnectionValidator).to receive(:new)

      post admin_system_status_test_connection_path, params: {
        smtp_config: smtp_params[:smtp_config].merge(address: ""),
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error_code"]).to eq("INVALID_CONFIGURATION")
      expect(SmtpConnectionValidator).not_to have_received(:new)
    end
  end

  describe "POST /admin/system_status/test_email" do
    it "rejects blank recipients" do
      sign_in admin

      post admin_system_status_test_email_path, params: { test_recipient: "" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["success"]).to be(false)
    end

    it "sends a test email" do
      sign_in admin
      delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      allow(Setting).to receive(:apply_smtp_settings!)
      allow(AdminMailer).to receive(:test_connection_email).with("ops@example.com").and_return(delivery)

      post admin_system_status_test_email_path, params: { test_recipient: "ops@example.com" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
    end

    it "returns smtp errors" do
      sign_in admin
      delivery = instance_double(ActionMailer::MessageDelivery)
      allow(Setting).to receive(:apply_smtp_settings!)
      allow(AdminMailer).to receive(:test_connection_email).and_return(delivery)
      allow(delivery).to receive(:deliver_now).and_raise(StandardError, "SMTP down")

      post admin_system_status_test_email_path, params: { test_recipient: "ops@example.com" }, as: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["error"]).to include("SMTP Error: SMTP down")
    end
  end

  describe "POST /admin/system_status/restart_server" do
    it "touches the restart file" do
      sign_in admin
      allow(FileUtils).to receive(:mkdir_p)
      allow(FileUtils).to receive(:touch)

      post admin_system_status_restart_server_path, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(FileUtils).to have_received(:mkdir_p)
      expect(FileUtils).to have_received(:touch)
    end
  end
end

# ---- merged from system_status_coverage_spec.rb ----
RSpec.describe "Admin::SystemStatus coverage additions", type: :request do
  let(:admin) { create(:user, :admin) }

  before { sign_in admin }

  it "builds a full diagnostic report with healthy redis and storage" do
    allow(Setting).to receive(:get).with("smtp_settings").and_return({})
    allow(Setting).to receive(:get).with("notification_rules").and_return({})
    redis = instance_double("Redis", info: { "redis_version" => "7.2" })
    allow(Sidekiq).to receive(:redis).and_yield(redis)
    stats = instance_double(Sidekiq::Stats, enqueued: 1, processed: 2, failed: 3)
    allow(Sidekiq::Stats).to receive(:new).and_return(stats)
    allow(Sidekiq::Workers).to receive(:new).and_return(double(size: 4))
    allow(Sidekiq::ProcessSet).to receive(:new).and_return(double(size: 5))
    service = double("storage", upload: true, download: "1", delete: true)
    allow(ActiveStorage::Blob).to receive(:service).and_return(service)

    get "/admin/system_status.json", as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("app_server", "status")).to eq("healthy")
    expect(response.parsed_body.dig("cache_queue", "redis_version")).to eq("7.2")
    expect(response.parsed_body.dig("storage_backend", "status")).to eq("healthy")
  end

  it "reports degraded redis and unreachable storage when diagnostics fail" do
    allow(Setting).to receive(:get).and_return({})
    allow(Sidekiq).to receive(:redis).and_raise(StandardError, "redis down")
    service = double("storage")
    allow(service).to receive(:upload).and_raise(StandardError, "disk down")
    allow(ActiveStorage::Blob).to receive(:service).and_return(service)

    get "/admin/system_status.json", as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("cache_queue", "status")).to eq("degraded")
    expect(response.parsed_body.dig("storage_backend", "status")).to eq("unreachable")
  end

  it "reports offline database status when the connection is inactive" do
    allow(Setting).to receive(:get).and_return({})
    allow_any_instance_of(Admin::SystemStatusController).to receive(:system_uptime).and_return("up") # rubocop:disable RSpec/AnyInstance

    pool = instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool, size: 5, stat: { connections: 2 })
    connection = instance_double(
      ActiveRecord::ConnectionAdapters::AbstractAdapter,
      active?: false,
      adapter_name: "PostgreSQL",
      pool: pool
    )
    allow(ActiveRecord::Base).to receive(:connection).and_return(connection)

    redis = instance_double("Redis", info: { "redis_version" => "7.2" })
    allow(Sidekiq).to receive(:redis).and_yield(redis)
    allow(Sidekiq::Stats).to receive(:new).and_return(instance_double(Sidekiq::Stats, enqueued: 0, processed: 0, failed: 0))
    allow(Sidekiq::Workers).to receive(:new).and_return(double(size: 0))
    allow(Sidekiq::ProcessSet).to receive(:new).and_return(double(size: 0))
    service = double("storage", upload: true, download: "1", delete: true)
    allow(ActiveStorage::Blob).to receive(:service).and_return(service)

    get "/admin/system_status.json", as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("database", "status")).to eq("offline")
  end

  it "falls back to an unknown redis version when redis info is unavailable" do
    allow(Setting).to receive(:get).and_return({})
    allow_any_instance_of(Admin::SystemStatusController).to receive(:system_uptime).and_return("up") # rubocop:disable RSpec/AnyInstance

    redis = instance_double("Redis", info: nil)
    allow(Sidekiq).to receive(:redis).and_yield(redis)
    allow(Sidekiq::Stats).to receive(:new).and_return(instance_double(Sidekiq::Stats, enqueued: 0, processed: 0, failed: 0))
    allow(Sidekiq::Workers).to receive(:new).and_return(double(size: 1))
    allow(Sidekiq::ProcessSet).to receive(:new).and_return(double(size: 1))
    service = double("storage", upload: true, download: "1", delete: true)
    allow(ActiveStorage::Blob).to receive(:service).and_return(service)

    get "/admin/system_status.json", as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("cache_queue", "redis_version")).to eq("Unknown")
  end

  it "returns restart errors when the trigger file cannot be touched" do
    allow(FileUtils).to receive(:mkdir_p)
    allow(FileUtils).to receive(:touch).and_raise(StandardError, "readonly")

    post "/admin/system_status/restart_server", as: :json

    expect(response).to have_http_status(:internal_server_error)
    expect(response.parsed_body["error"]).to include("readonly")
  end
end
