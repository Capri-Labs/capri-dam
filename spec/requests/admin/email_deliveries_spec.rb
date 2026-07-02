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

# ---- merged from email_deliveries_coverage_spec.rb ----
RSpec.describe "Admin::EmailDeliveries coverage additions", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:template) { create(:email_template, name: "Digest") }

  before do
    sign_in admin
    allow(EmailDispatcherWorker).to receive(:perform_async)
  end

  describe "GET /admin/email_deliveries" do
    it "filters by search and date range, clamps pagination, and serializes retries" do
      matching = create(:email_delivery, email_template: template, recipient_email: "match@example.com", status: "failed", retry_count: 2)
      matching.update!(created_at: Time.zone.parse("2026-07-01 10:00"))
      create(:email_delivery, email_template: template, recipient_email: "other@example.com", status: "failed", created_at: Time.zone.parse("2026-06-01 10:00"))

      get "/admin/email_deliveries", params: {
        search: " match ", status: "failed", date_from: "2026-07-01", date_to: "2026-07-01", per_page: 500, page: -4
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["email_deliveries"].map { |row| row["recipient"] }).to eq([ "match@example.com" ])
      expect(response.parsed_body["email_deliveries"].first).to include("retry_count" => 2, "template_name" => "Digest")
      expect(response.parsed_body["pagination"]).to include("page" => 1, "per_page" => 100, "total" => 1)
    end

    it "returns an empty page when filters match nothing" do
      create(:email_delivery, email_template: template, recipient_email: "person@example.com", status: "sent")

      get "/admin/email_deliveries", params: { search: "nobody", page: 2, per_page: 1 }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["email_deliveries"]).to eq([])
      expect(response.parsed_body["pagination"]["total_pages"]).to eq(0)
    end
  end

  describe "GET /admin/email_deliveries/stats" do
    it "returns delivery counters" do
      create(:email_delivery, email_template: template, status: "sent")
      create(:email_delivery, email_template: template, status: "failed")
      create(:email_delivery, email_template: template, status: "pending")

      get "/admin/email_deliveries/stats", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("total" => 3, "sent" => 1, "failed" => 1, "pending" => 1)
    end
  end

  describe "POST /admin/email_deliveries/bulk_retry_failed" do
    it "resets all failed deliveries and queues them" do
      failed_one = create(:email_delivery, email_template: template, status: "failed", retry_count: 3, error_log: "one")
      failed_two = create(:email_delivery, email_template: template, status: "failed", retry_count: 1, error_log: "two")
      sent = create(:email_delivery, email_template: template, status: "sent")

      post "/admin/email_deliveries/bulk_retry_failed", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["retried_count"]).to eq(2)
      expect([ failed_one.reload.status, failed_two.reload.status, sent.reload.status ]).to eq(%w[pending pending sent])
      expect(EmailDispatcherWorker).to have_received(:perform_async).with(failed_one.id)
      expect(EmailDispatcherWorker).to have_received(:perform_async).with(failed_two.id)
    end

    it "handles no failed deliveries" do
      create(:email_delivery, email_template: template, status: "sent")

      post "/admin/email_deliveries/bulk_retry_failed", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["retried_count"]).to eq(0)
      expect(EmailDispatcherWorker).not_to have_received(:perform_async)
    end
  end
end
