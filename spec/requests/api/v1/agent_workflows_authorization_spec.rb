# frozen_string_literal: true

require "rails_helper"

# Behavioural (non-rswag) request specs that exercise authentication and
# authorization for the Agent Workflows API.  Unlike the rswag doc specs,
# these control the Devise session directly so we can assert 401/403 paths.
RSpec.describe "Api::V1::AgentWorkflows authorization", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user)  { create(:user) }

  describe "GET /api/v1/agent_workflows" do
    it "returns 401 when unauthenticated" do
      get "/api/v1/agent_workflows"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 200 for a regular signed-in user" do
      sign_in user
      create(:agent_workflow)
      get "/api/v1/agent_workflows"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(1)
    end
  end

  describe "POST /api/v1/agent_workflows" do
    let(:valid) do
      { agent_workflow: { name: "SEO Bot", trigger_event: "asset.staged", agent_model: "gpt-4o-mini" } }
    end

    it "forbids a non-admin user" do
      sign_in user
      post "/api/v1/agent_workflows", params: valid, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "allows an admin and records created_by" do
      sign_in admin
      expect {
        post "/api/v1/agent_workflows", params: valid, as: :json
      }.to change(AgentWorkflow, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(AgentWorkflow.last.created_by).to eq(admin)
    end

    it "returns 422 on invalid data" do
      sign_in admin
      post "/api/v1/agent_workflows",
           params: { agent_workflow: { name: "", trigger_event: "nope", agent_model: "" } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/agent_workflows/:id/toggle" do
    let(:workflow) { create(:agent_workflow, active: false) }

    it "flips active and is admin-only" do
      sign_in admin
      patch "/api/v1/agent_workflows/#{workflow.id}/toggle"
      expect(response).to have_http_status(:ok)
      expect(workflow.reload.active).to be(true)
    end

    it "forbids non-admins" do
      sign_in user
      patch "/api/v1/agent_workflows/#{workflow.id}/toggle"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/agent_workflows/:id/executions (gateway secret)" do
    let(:workflow) { create(:agent_workflow) }

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("GATEWAY_SECRET", nil).and_return("s3cr3t")
    end

    it "rejects requests without the secret header" do
      post "/api/v1/agent_workflows/#{workflow.id}/executions",
           params: { agent_execution: { status: "success" } }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a wrong secret" do
      post "/api/v1/agent_workflows/#{workflow.id}/executions",
           params: { agent_execution: { status: "success" } }, as: :json,
           headers: { "X-Gateway-Secret" => "wrong" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts a correct secret and creates an execution" do
      expect {
        post "/api/v1/agent_workflows/#{workflow.id}/executions",
             params: { agent_execution: { status: "success", summary: "Mapped 4 tags", duration_ms: 1400 } },
             as: :json,
             headers: { "X-Gateway-Secret" => "s3cr3t" }
      }.to change(AgentExecution, :count).by(1)
      expect(response).to have_http_status(:created)
    end
  end
end
