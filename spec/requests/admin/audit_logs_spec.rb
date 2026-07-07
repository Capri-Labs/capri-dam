require "rails_helper"

RSpec.describe "Admin::AuditLogs", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user)  { create(:user) }

  describe "GET /admin/audit_logs" do
    it "redirects unauthenticated users to sign in" do
      get admin_audit_logs_path, as: :json

      expect(response).to redirect_to(new_user_session_path(format: :json))
    end

    it "returns forbidden for non-admin users" do
      sign_in user

      get admin_audit_logs_path, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "lists audit logs ordered newest-first with pagination metadata" do
      sign_in admin
      older = create(:audit_log, user: admin, action: "update", created_at: 2.days.ago)
      newer = create(:audit_log, user: admin, action: "create", created_at: 1.hour.ago)

      get admin_audit_logs_path, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      ids = body["audit_logs"].map { |l| l["id"] }
      expect(ids.index(newer.id)).to be < ids.index(older.id)
      expect(body["pagination"]).to include("page" => 1, "per_page" => 25, "total" => 2)
    end

    it "filters by user_id" do
      sign_in admin
      other_user = create(:user)
      mine   = create(:audit_log, user: admin)
      theirs = create(:audit_log, user: other_user)

      get admin_audit_logs_path, params: { user_id: admin.id }, as: :json

      ids = response.parsed_body["audit_logs"].map { |l| l["id"] }
      expect(ids).to include(mine.id)
      expect(ids).not_to include(theirs.id)
    end

    it "filters by action" do
      sign_in admin
      create(:audit_log, user: admin, action: "create")
      destroy_log = create(:audit_log, user: admin, action: "destroy")

      get admin_audit_logs_path, params: { audit_action: "destroy" }, as: :json

      ids = response.parsed_body["audit_logs"].map { |l| l["id"] }
      expect(ids).to eq([ destroy_log.id ])
    end

    it "filters by auditable_type" do
      sign_in admin
      folder_log = create(:audit_log, user: admin, auditable_type: "Folder")
      create(:audit_log, user: admin, auditable_type: "Asset")

      get admin_audit_logs_path, params: { auditable_type: "Folder" }, as: :json

      ids = response.parsed_body["audit_logs"].map { |l| l["id"] }
      expect(ids).to eq([ folder_log.id ])
    end

    it "filters by impersonated flag" do
      sign_in admin
      impersonated_log = create(:audit_log, user: admin, true_user: admin, impersonated: true)
      create(:audit_log, user: admin, impersonated: false)

      get admin_audit_logs_path, params: { impersonated: "true" }, as: :json

      ids = response.parsed_body["audit_logs"].map { |l| l["id"] }
      expect(ids).to eq([ impersonated_log.id ])
    end

    it "filters by created_at date range" do
      sign_in admin
      in_range = create(:audit_log, user: admin, created_at: Date.new(2026, 1, 15).noon)
      create(:audit_log, user: admin, created_at: Date.new(2026, 2, 1).noon)

      get admin_audit_logs_path, params: { date_from: "2026-01-01", date_to: "2026-01-31" }, as: :json

      ids = response.parsed_body["audit_logs"].map { |l| l["id"] }
      expect(ids).to eq([ in_range.id ])
    end

    it "searches across actor email, action, and resource type" do
      sign_in admin
      match = create(:audit_log, user: admin, auditable_type: "Folder")

      get admin_audit_logs_path, params: { search: "folder" }, as: :json

      ids = response.parsed_body["audit_logs"].map { |l| l["id"] }
      expect(ids).to include(match.id)
    end

    it "paginates results" do
      sign_in admin
      create_list(:audit_log, 3, user: admin)

      get admin_audit_logs_path, params: { per_page: 2, page: 2 }, as: :json

      body = response.parsed_body
      expect(body["audit_logs"].length).to eq(1)
      expect(body["pagination"]).to include("page" => 2, "per_page" => 2, "total" => 3, "total_pages" => 2)
    end

    it "includes distinct filter_options for actions and auditable_types" do
      sign_in admin
      create(:audit_log, user: admin, action: "create", auditable_type: "Folder")
      create(:audit_log, user: admin, action: "destroy", auditable_type: "Asset")

      get admin_audit_logs_path, as: :json

      options = response.parsed_body["filter_options"]
      expect(options["actions"]).to match_array(%w[create destroy])
      expect(options["auditable_types"]).to match_array(%w[Asset Folder])
    end

    it "serializes actor and true_user summaries" do
      sign_in admin
      log = create(:audit_log, user: admin, true_user: admin, impersonated: true)

      get admin_audit_logs_path, as: :json

      entry = response.parsed_body["audit_logs"].find { |l| l["id"] == log.id }
      expect(entry["user"]).to include("id" => admin.id, "email" => admin.email)
      expect(entry["true_user"]).to include("id" => admin.id, "email" => admin.email)
      expect(entry["impersonated"]).to be true
    end
  end
end
