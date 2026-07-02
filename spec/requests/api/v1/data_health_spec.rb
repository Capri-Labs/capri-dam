require "rails_helper"

RSpec.describe "Api::V1::DataHealth", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  describe "GET /api/v1/data_health/overview" do
    before do
      create(:system_connector, status: "active")
      create(:system_connector, status: "idle")
      create(:system_connector, status: "disabled")
      allow(IngestionBatch).to receive(:aggregate_stats).and_return(
        total_batches: 3,
        active_batches: 1,
        completed_batches: 1,
        failed_batches: 1,
        total_duplicates_blocked: 2,
        total_assets_committed: 10,
        total_assets_staged: 12,
        estimated_storage_saved_gb: 1.5,
        estimated_cost_savings_usd: 0.25,
      )
      allow_any_instance_of(Api::V1::DataHealthController).to receive(:duplicate_group_stats).and_return(
        pending: 1, resolved: 2, dismissed: 3, total: 6
      )
      allow_any_instance_of(Api::V1::DataHealthController).to receive(:current_scan_status).and_return(
        status: "idle", progress: {}, last_scan_at: nil
      )
      allow_any_instance_of(Api::V1::DataHealthController).to receive(:build_storage_metrics).and_return("active_used_tb" => 1.2)
      allow_any_instance_of(Api::V1::DataHealthController).to receive(:build_batch_overview).and_return(
        total: 3, active: 1, completed: 1, failed: 1
      )
      allow_any_instance_of(Api::V1::DataHealthController).to receive(:build_debt_flags).and_return([ { type: "duplicates" } ])
    end

    it "requires authentication" do
      get overview_api_v1_data_health_index_path, as: :json

      expect(response.status).to be_in([ 401, 302 ])
    end

    it "rejects non-admin users" do
      sign_in user

      get overview_api_v1_data_health_index_path, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "returns the overview payload for admins" do
      sign_in admin

      get overview_api_v1_data_health_index_path, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["connectors"]).to include("total" => 3, "active" => 1, "idle" => 1, "disabled" => 1)
      expect(response.parsed_body["generated_at"]).to be_present
    end
  end

  describe "GET /api/v1/data_health/connectors" do
    it "returns connector health details" do
      sign_in admin
      connector = create(:system_connector, name: "AEM", status: "active", analysis_report: { "total_found" => 10, "missing_tags" => 1 })
      create(:ingestion_batch, connector: connector)

      get connectors_api_v1_data_health_index_path, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.first).to include(
        "name" => "AEM",
        "provider_type" => connector.provider_type,
        "batches_count" => 1,
      )
    end
  end

  describe "POST /api/v1/data_health/remediate" do
    it "queues remediation jobs for admins" do
      sign_in admin
      allow(DataHealthRemediationWorker).to receive(:perform_async)

      post remediate_api_v1_data_health_index_path, params: { debt_type: "duplicates" }, as: :json

      expect(response).to have_http_status(:accepted)
      expect(DataHealthRemediationWorker).to have_received(:perform_async).with("duplicates", admin.id)
    end

    it "rejects unknown debt types" do
      sign_in admin

      post remediate_api_v1_data_health_index_path, params: { debt_type: "unknown" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects non-admin users" do
      sign_in user

      post remediate_api_v1_data_health_index_path, params: { debt_type: "duplicates" }, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end

# ---- merged from data_health_coverage_spec.rb ----
RSpec.describe "Api::V1::DataHealth coverage", type: :request do
  let(:admin) { create(:user, admin: true) }
  let(:user) { create(:user) }

  def json = response.parsed_body

  before do
    allow(DataHealthRemediationWorker).to receive(:perform_async)
  end

  describe "GET /api/v1/data_health/overview" do
    before do
      Setting.set("duplicate_manager_scan_status", "running")
      Setting.set("duplicate_manager_scan_progress", { processed: 3, total: 5 })
      Setting.set("duplicate_manager_last_scan_at", "2026-07-01T12:00:00Z")

      create(:duplicate_group, status: "pending")
      create(:duplicate_group, :resolved)
      create(:duplicate_group, :dismissed)
      create(:system_connector, status: "active", analysis_report: { "missing_tags" => 250 })
      create(:system_connector, status: "idle")
      create(:system_connector, status: "disabled")
      create(:ingestion_batch, status: :review_needed, total_count: 4, committed_count: 1, duplicate_count: 2)
      batch = create(:ingestion_batch, status: :committed, total_count: 6, committed_count: 6, duplicate_count: 1)
      create(:ingestion_item, ingestion_batch: batch, status: :flagged_duplicate, file_size: 2.terabytes,
                              original_filename: "dupe.jpg")
      create(:asset, user: admin, properties: { "file_size" => 1.terabyte.to_s, "content_type" => "image/png" })
      create(:asset, user: admin, properties: { "file_size" => "", "copyright" => "Licensed" })
    end

    it "requires an admin session" do
      sign_in user

      get "/api/v1/data_health/overview", as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "builds the real dashboard metrics and debt flags" do
      sign_in admin

      get "/api/v1/data_health/overview", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["storage"]).to include(
        "duplicates_prevented_tb" => 2.0,
        "active_used_tb" => 1.0,
        "orphaned_wasted_tb" => 1.0,
        "total_duplicates_blocked" => 3,
      )
      expect(json["duplicates"]).to include("pending" => 1, "resolved" => 1, "dismissed" => 1, "total" => 3)
      expect(json["connectors"]).to include("total" => 3, "active" => 1, "idle" => 1, "disabled" => 1)
      expect(json["scan"]).to include("status" => "running", "progress" => { "processed" => 3, "total" => 5 })
      expect(json["debt_flags"].pluck("type")).to eq(%w[duplicates missing_metadata copyright review_pipeline])
      expect(json["debt_flags"].find { |flag| flag["type"] == "missing_metadata" }).to include(
        "count" => 250,
        "impact" => "High",
        "can_automate" => true,
      )
      expect(json["debt_flags"].find { |flag| flag["type"] == "review_pipeline" }).to include(
        "count" => 1,
        "impact" => "Medium",
      )
    end
  end

  describe "GET /api/v1/data_health/connectors" do
    it "serializes health scores for active, stale, and disabled connectors" do
      sign_in admin
      create(:system_connector, name: "Disabled", status: "disabled")
      stale = create(:system_connector, name: "Stale", status: "idle", last_sync: 8.days.ago,
                                         analysis_report: { "total_found" => 10, "missing_tags" => 5 })
      create(:ingestion_batch, connector: stale)
      create(:system_connector, name: "Healthy", status: "active", last_sync: 1.day.ago,
                                       analysis_report: { "total_found" => 10, "missing_tags" => 1 })

      get "/api/v1/data_health/connectors", as: :json

      expect(response).to have_http_status(:ok)
      expect(json.map { |connector| connector["name"] }).to eq(%w[Disabled Healthy Stale])
      expect(json.find { |connector| connector["name"] == "Disabled" }["health_score"]).to be_nil
      expect(json.find { |connector| connector["name"] == "Stale" }).to include(
        "batches_count" => 1,
        "health_score" => 20,
      )
    end
  end

  describe "POST /api/v1/data_health/remediate" do
    it "queues known debt types and rejects unknown ones" do
      sign_in admin

      post "/api/v1/data_health/remediate", params: { debt_type: " missing_metadata " }, as: :json
      expect(response).to have_http_status(:accepted)
      expect(DataHealthRemediationWorker).to have_received(:perform_async).with("missing_metadata", admin.id)

      post "/api/v1/data_health/remediate", params: { debt_type: "bogus" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to include("Unknown debt type")
    end
  end
end
