# frozen_string_literal: true

require "rails_helper"

# Behavioural (non-rswag) request specs covering authentication and
# authorization for the AI Batch Tasks API, plus the worker-dispatch and
# gateway-secret callback paths.
RSpec.describe "Api::V1::AiBatchJobs authorization", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user)  { create(:user) }

  describe "GET /api/v1/ai_batch_jobs" do
    it "returns 401 when unauthenticated" do
      get "/api/v1/ai_batch_jobs"
      expect(response).to have_http_status(:unauthorized)
    end

    it "forbids a regular signed-in user (admin-only screen)" do
      sign_in user
      get "/api/v1/ai_batch_jobs"
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 200 for an admin" do
      sign_in admin
      create(:ai_batch_job)
      get "/api/v1/ai_batch_jobs"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["jobs"].size).to eq(1)
    end
  end

  describe "GET /api/v1/ai_batch_jobs/task_types" do
    it "returns the registry metadata for an admin" do
      sign_in admin
      get "/api/v1/ai_batch_jobs/task_types"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["tasks"]).to be_an(Array).and be_present
      expect(body["scopes"]).to be_an(Array).and be_present
    end
  end

  describe "POST /api/v1/ai_batch_jobs" do
    let(:valid) { { ai_batch_job: { task_type: "metadata_extraction", target_scope: "all_assets" } } }

    it "forbids a non-admin" do
      sign_in user
      post "/api/v1/ai_batch_jobs", params: valid, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "creates a queued job, records created_by and enqueues the worker" do
      sign_in admin
      expect {
        post "/api/v1/ai_batch_jobs", params: valid, as: :json
      }.to change(AiBatchJob, :count).by(1)
        .and change(AiBatchJobWorker.jobs, :size).by(1)
      expect(response).to have_http_status(:created)
      job = AiBatchJob.last
      expect(job.created_by).to eq(admin)
      expect(job.status).to eq("queued")
    end

    it "returns 422 on invalid data" do
      sign_in admin
      post "/api/v1/ai_batch_jobs", params: { ai_batch_job: { task_type: "x", target_scope: "y" } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/v1/ai_batch_jobs/:id/cancel" do
    it "cancels an active job (admin only)" do
      sign_in admin
      job = create(:ai_batch_job, :running)
      post "/api/v1/ai_batch_jobs/#{job.id}/cancel"
      expect(response).to have_http_status(:ok)
      expect(job.reload.status).to eq("cancelled")
    end

    it "rejects cancelling an already-terminal job" do
      sign_in admin
      job = create(:ai_batch_job, :completed)
      post "/api/v1/ai_batch_jobs/#{job.id}/cancel"
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "forbids non-admins" do
      sign_in user
      job = create(:ai_batch_job, :running)
      post "/api/v1/ai_batch_jobs/#{job.id}/cancel"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/ai_batch_jobs/:id/progress (gateway secret)" do
    let(:job) { create(:ai_batch_job, :running) }

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("GATEWAY_SECRET", nil).and_return("s3cr3t")
    end

    it "rejects requests without the secret header" do
      post "/api/v1/ai_batch_jobs/#{job.id}/progress",
           params: { ai_batch_job: { processed_count: 5 } }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a wrong secret" do
      post "/api/v1/ai_batch_jobs/#{job.id}/progress",
           params: { ai_batch_job: { processed_count: 5 } }, as: :json,
           headers: { "X-Gateway-Secret" => "wrong" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "updates counters with a correct secret" do
      post "/api/v1/ai_batch_jobs/#{job.id}/progress",
           params: { ai_batch_job: { processed_count: 80, succeeded_count: 78, failed_count: 2 } },
           as: :json, headers: { "X-Gateway-Secret" => "s3cr3t" }
      expect(response).to have_http_status(:ok)
      expect(job.reload.processed_count).to eq(80)
    end

    it "sets completed_at when a terminal status is reported" do
      post "/api/v1/ai_batch_jobs/#{job.id}/progress",
           params: { ai_batch_job: { status: "completed", processed_count: 100 } },
           as: :json, headers: { "X-Gateway-Secret" => "s3cr3t" }
      expect(response).to have_http_status(:ok)
      expect(job.reload.completed_at).to be_present
    end
  end
end
