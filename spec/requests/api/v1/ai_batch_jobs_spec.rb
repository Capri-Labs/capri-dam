# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Api::V1::AiBatchJobs", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user)  { create(:user) }

  # ===========================================================================
  # INDEX / CREATE — /api/v1/ai_batch_jobs
  # ===========================================================================
  path "/api/v1/ai_batch_jobs" do
    get "List AI batch jobs (admin only)" do
      tags     "AI Batch Tasks"
      produces "application/json"
      security [ Bearer: [] ]
      description "Returns recent AI batch task runs with live progress counters."

      response "200", "Jobs returned" do
        schema type: :object,
               properties: {
                 total:    { type: :integer },
                 page:     { type: :integer },
                 per_page: { type: :integer },
                 jobs:     { type: :array, items: { "$ref" => "#/components/schemas/AiBatchJob" } },
               }
        before do
          sign_in admin
          create_list(:ai_batch_job, 2)
        end
        run_test!
      end
    end

    post "Launch an AI batch job (admin only)" do
      tags     "AI Batch Tasks"
      consumes "application/json"
      produces "application/json"
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[ai_batch_job],
        properties: {
          ai_batch_job: {
            type: :object,
            required: %w[task_type target_scope],
            properties: {
              task_type:    { type: :string, example: "metadata_extraction" },
              target_scope: { type: :string, example: "missing_metadata" },
              concurrency:  { type: :integer, example: 25 },
              options:      { type: :object },
            },
          },
        },
      }

      response "201", "Job created and queued" do
        schema "$ref" => "#/components/schemas/AiBatchJob"
        before { sign_in admin }
        let(:payload) do
          { ai_batch_job: { task_type: "metadata_extraction", target_scope: "all_assets" } }
        end
        run_test!
      end

      response "422", "Validation failed" do
        before { sign_in admin }
        let(:payload) { { ai_batch_job: { task_type: "bad", target_scope: "bad" } } }
        run_test!
      end

      response "403", "Non-admin forbidden" do
        before { sign_in user }
        let(:payload) do
          { ai_batch_job: { task_type: "metadata_extraction", target_scope: "all_assets" } }
        end
        run_test!
      end
    end
  end

  # ===========================================================================
  # TASK TYPES — GET /api/v1/ai_batch_jobs/task_types
  # ===========================================================================
  path "/api/v1/ai_batch_jobs/task_types" do
    get "List available AI task types and datasets (admin only)" do
      tags     "AI Batch Tasks"
      produces "application/json"
      security [ Bearer: [] ]
      description "Registry metadata used to drive the data-driven batch configuration form."

      response "200", "Registry returned" do
        schema type: :object,
               properties: {
                 tasks:  { type: :array, items: { type: :object } },
                 scopes: { type: :array, items: { type: :object } },
               }
        before { sign_in admin }
        run_test!
      end
    end
  end

  # ===========================================================================
  # SHOW / CANCEL — /api/v1/ai_batch_jobs/:id
  # ===========================================================================
  path "/api/v1/ai_batch_jobs/{id}" do
    parameter name: :id, in: :path, type: :integer

    get "Fetch a single job" do
      tags     "AI Batch Tasks"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Job returned" do
        schema "$ref" => "#/components/schemas/AiBatchJob"
        let(:job) { create(:ai_batch_job) }
        let(:id)  { job.id }
        before { sign_in admin }
        run_test!
      end

      response "404", "Not found" do
        let(:id) { 0 }
        before { sign_in admin }
        run_test!
      end
    end
  end

  path "/api/v1/ai_batch_jobs/{id}/cancel" do
    parameter name: :id, in: :path, type: :integer

    post "Cancel a running job (admin only)" do
      tags     "AI Batch Tasks"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Job cancelled" do
        schema "$ref" => "#/components/schemas/AiBatchJob"
        let(:job) { create(:ai_batch_job, :running) }
        let(:id)  { job.id }
        before { sign_in admin }
        run_test! do |response|
          expect(JSON.parse(response.body)["status"]).to eq("cancelled")
        end
      end
    end
  end

  # ===========================================================================
  # PROGRESS — POST /api/v1/ai_batch_jobs/:id/progress (gateway secret)
  # ===========================================================================
  path "/api/v1/ai_batch_jobs/{id}/progress" do
    parameter name: :id, in: :path, type: :integer

    post "Stream progress (AI Gateway, secret-authenticated)" do
      tags     "AI Batch Tasks"
      consumes "application/json"
      produces "application/json"
      description "Internal endpoint called by the AI Gateway with the X-Gateway-Secret header to update progress counters."

      parameter name: "X-Gateway-Secret", in: :header, type: :string, required: true
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[ai_batch_job],
        properties: {
          ai_batch_job: {
            type: :object,
            properties: {
              status:          { type: :string, enum: %w[queued running paused completed failed cancelled] },
              processed_count: { type: :integer },
              succeeded_count: { type: :integer },
              failed_count:    { type: :integer },
            },
          },
        },
      }

      response "200", "Progress recorded" do
        let(:job) { create(:ai_batch_job, :running) }
        let(:id)  { job.id }
        let(:payload) { { ai_batch_job: { processed_count: 60, succeeded_count: 58, failed_count: 2 } } }
        let("X-Gateway-Secret") { "test-secret" }
        before do
          allow(ENV).to receive(:fetch).and_call_original
          allow(ENV).to receive(:fetch).with("GATEWAY_SECRET", nil).and_return("test-secret")
        end
        run_test!
      end

      response "401", "Missing/invalid gateway secret" do
        let(:job) { create(:ai_batch_job, :running) }
        let(:id)  { job.id }
        let(:payload) { { ai_batch_job: { processed_count: 1 } } }
        let("X-Gateway-Secret") { "wrong-secret" }
        run_test!
      end
    end
  end
end
