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

      post admin_system_status_update_smtp_path, params: smtp_params, as: :json

      expect(response).to have_http_status(:ok)
      expect(Setting).to have_received(:set).with("smtp_settings", hash_including("address" => "smtp.example.com"))
      expect(Setting).to have_received(:apply_smtp_settings!)
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
