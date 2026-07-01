require "rails_helper"

RSpec.describe "Admin::EmailDeliveries", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }
  let(:template) { create(:email_template, name: "Password Reset") }
  let!(:failed_delivery) do
    create(:email_delivery,
           email_template: template,
           status: "failed",
           retry_count: 2,
           error_log: "SMTP timeout")
  end
  let!(:sent_delivery) { create(:email_delivery, email_template: template, status: "sent") }

  describe "GET /admin/email_deliveries" do
    it "redirects unauthenticated users to sign in" do
      get admin_email_deliveries_path, as: :json

      expect(response).to redirect_to(new_user_session_path(format: :json))
    end

    it "returns forbidden for non-admin users" do
      sign_in user

      get admin_email_deliveries_path, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "returns recent delivery logs for admins" do
      sign_in admin

      get admin_email_deliveries_path, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["email_deliveries"].size).to eq(2)
      expect(response.parsed_body["email_deliveries"].first["template_name"]).to eq("Password Reset")
    end

    it "filters delivery logs by status" do
      sign_in admin

      get admin_email_deliveries_path, params: { status: "failed" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["email_deliveries"].map { |log| log["status"] }).to eq([ "failed" ])
    end
  end

  describe "POST /admin/email_deliveries/:id/retry" do
    it "requeues failed deliveries for admins" do
      sign_in admin
      allow(EmailDispatcherWorker).to receive(:perform_async)

      post retry_admin_email_delivery_path(failed_delivery), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(failed_delivery.reload).to have_attributes(status: "pending", retry_count: 0, error_log: nil)
      expect(EmailDispatcherWorker).to have_received(:perform_async).with(failed_delivery.id)
    end

    it "does not requeue sent deliveries" do
      sign_in admin
      allow(EmailDispatcherWorker).to receive(:perform_async)

      post retry_admin_email_delivery_path(sent_delivery), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(false)
      expect(EmailDispatcherWorker).not_to have_received(:perform_async)
    end
  end
end
