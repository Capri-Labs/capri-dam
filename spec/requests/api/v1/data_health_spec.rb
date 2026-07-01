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
