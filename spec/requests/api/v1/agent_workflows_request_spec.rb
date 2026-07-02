# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::AgentWorkflows coverage", type: :request do
  let(:admin) { create(:user, admin: true) }
  let(:user) { create(:user) }
  let(:redis) { instance_double("Redis", publish: 1) }

  def json = response.parsed_body

  before do
    allow(Sidekiq).to receive(:redis).and_yield(redis)
  end

  describe "read endpoints" do
    it "lists and shows workflows with computed execution stats" do
      sign_in user
      workflow = create(:agent_workflow, name: "Older", created_by: admin, updated_at: 2.days.ago)
      create(:agent_execution, agent_workflow: workflow, status: "success", duration_ms: 100)
      create(:agent_execution, agent_workflow: workflow, status: "failed", duration_ms: 300)
      newer = create(:agent_workflow, name: "Newer", created_by: admin, updated_at: 1.hour.ago)

      get "/api/v1/agent_workflows", as: :json

      expect(response).to have_http_status(:ok)
      expect(json.first).to include("id" => newer.id, "execution_count" => 0)
      expect(json.second).to include(
        "id" => workflow.id,
        "created_by" => admin.email,
        "reliability" => 50.0,
        "avg_duration_ms" => 200,
        "execution_count" => 2,
      )

      get "/api/v1/agent_workflows/#{workflow.id}", as: :json
      expect(response).to have_http_status(:ok)
      expect(json).to include("name" => "Older")
    end

    it "returns not found for missing workflow ids" do
      sign_in user

      get "/api/v1/agent_workflows/0", as: :json

      expect(response).to have_http_status(:not_found)
      expect(json["error"]).to eq("Agent workflow not found.")
    end
  end

  describe "admin writes" do
    before { sign_in admin }

    it "creates, updates, toggles, and destroys workflows" do
      expect do
        post "/api/v1/agent_workflows", params: {
          agent_workflow: {
            name: "SEO Bot",
            trigger_event: "manual",
            agent_model: "gpt-4o-mini",
            tools_enabled: %w[Tagger Summarizer],
            active: true,
            metadata: { "team" => "metadata" },
          },
        }, as: :json
      end.to change(AgentWorkflow, :count).by(1)
      expect(response).to have_http_status(:created)
      workflow = AgentWorkflow.last
      expect(workflow.created_by).to eq(admin)
      expect(json).to include("active" => true, "tools_enabled" => %w[Tagger Summarizer])

      patch "/api/v1/agent_workflows/#{workflow.id}", params: { agent_workflow: { name: "Renamed" } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(workflow.reload.name).to eq("Renamed")

      patch "/api/v1/agent_workflows/#{workflow.id}/toggle", as: :json
      expect(response).to have_http_status(:ok)
      expect(json).to include("id" => workflow.id, "active" => false)

      delete "/api/v1/agent_workflows/#{workflow.id}", as: :json
      expect(response).to have_http_status(:no_content)
      expect(AgentWorkflow.exists?(workflow.id)).to be(false)
    end

    it "returns validation errors and trigger failures" do
      post "/api/v1/agent_workflows", params: { agent_workflow: { name: "", trigger_event: "bad", agent_model: "" } },
                                      as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"]).to be_present

      workflow = create(:agent_workflow)
      allow(Sidekiq).to receive(:redis).and_raise(Redis::BaseError, "offline")

      post "/api/v1/agent_workflows/#{workflow.id}/trigger", as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json["error"]).to include("offline")
    end

    it "publishes manual trigger payloads" do
      workflow = create(:agent_workflow)

      post "/api/v1/agent_workflows/#{workflow.id}/trigger", as: :json

      expect(response).to have_http_status(:ok)
      expect(redis).to have_received(:publish).with("ai_gateway_events", satisfy { |payload|
        JSON.parse(payload) == {
          "event" => "agent_workflow.manual_trigger",
          "workflow_id" => workflow.id,
          "triggered_by" => admin.id,
        }
      })
    end
  end

  describe "executions" do
    let(:workflow) { create(:agent_workflow) }

    it "paginates execution history" do
      sign_in user
      create_list(:agent_execution, 21, agent_workflow: workflow)

      get "/api/v1/agent_workflows/#{workflow.id}/executions", params: { page: 2 }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to include("total" => 21, "page" => 2, "per_page" => 20)
      expect(json["executions"].size).to eq(1)
    end

    it "authenticates gateway execution logs and defaults timestamps" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("GATEWAY_SECRET", nil).and_return("secret")

      post "/api/v1/agent_workflows/#{workflow.id}/executions",
           params: { agent_execution: { status: "running", trigger_type: "manual", trigger_payload: { asset_id: "a1" } } },
           headers: { "X-Gateway-Secret" => "secret" },
           as: :json

      expect(response).to have_http_status(:created)
      expect(json).to include("status" => "running", "completed_at" => nil)

      post "/api/v1/agent_workflows/#{workflow.id}/executions",
           params: { agent_execution: { status: "not-real" } },
           headers: { "X-Gateway-Secret" => "secret" },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"]).to be_present
    end
  end
end
