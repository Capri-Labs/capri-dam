# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Api::V1::AgentWorkflows", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user)  { create(:user) }

  # ===========================================================================
  # INDEX — GET /api/v1/agent_workflows
  # ===========================================================================
  path "/api/v1/agent_workflows" do
    get "List all agent workflows" do
      tags     "AI Agents"
      produces "application/json"
      security [ Bearer: [] ]
      description "Returns every agent workflow with computed reliability/latency stats. Available to any authenticated user."

      response "200", "Workflows returned" do
        schema type: :array, items: { "$ref" => "#/components/schemas/AgentWorkflow" }
        before do
          sign_in user
          create_list(:agent_workflow, 2)
        end
        run_test!
      end
    end

    # -------------------------------------------------------------------------
    post "Create an agent workflow (admin only)" do
      tags     "AI Agents"
      consumes "application/json"
      produces "application/json"
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[agent_workflow],
        properties: {
          agent_workflow: {
            type: :object,
            required: %w[name trigger_event agent_model],
            properties: {
              name:          { type: :string, example: "Auto-SEO Enrichment" },
              description:   { type: :string },
              trigger_event: { type: :string, enum: AgentWorkflow::TRIGGER_EVENTS },
              agent_model:   { type: :string, example: "gpt-4o-mini" },
              tools_enabled: { type: :array, items: { type: :string } },
              active:        { type: :boolean },
            },
          },
        },
      }

      response "201", "Workflow created" do
        schema "$ref" => "#/components/schemas/AgentWorkflow"
        before { sign_in admin }
        let(:payload) do
          { agent_workflow: { name: "SEO Bot", trigger_event: "asset.staged", agent_model: "gpt-4o-mini" } }
        end
        run_test!
      end

      response "422", "Validation failed" do
        before { sign_in admin }
        let(:payload) { { agent_workflow: { name: "", trigger_event: "bad", agent_model: "" } } }
        run_test!
      end

      response "403", "Non-admin forbidden" do
        before { sign_in user }
        let(:payload) do
          { agent_workflow: { name: "SEO Bot", trigger_event: "asset.staged", agent_model: "gpt-4o-mini" } }
        end
        run_test!
      end
    end
  end

  # ===========================================================================
  # SHOW / UPDATE / DESTROY — /api/v1/agent_workflows/:id
  # ===========================================================================
  path "/api/v1/agent_workflows/{id}" do
    parameter name: :id, in: :path, type: :integer

    get "Fetch a single workflow" do
      tags     "AI Agents"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Workflow returned" do
        schema "$ref" => "#/components/schemas/AgentWorkflow"
        let(:workflow) { create(:agent_workflow) }
        let(:id)       { workflow.id }
        before { sign_in user }
        run_test!
      end

      response "404", "Not found" do
        let(:id) { 0 }
        before { sign_in user }
        run_test!
      end
    end

    patch "Update a workflow (admin only)" do
      tags     "AI Agents"
      consumes "application/json"
      produces "application/json"
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          agent_workflow: {
            type: :object,
            properties: { name: { type: :string }, active: { type: :boolean } },
          },
        },
      }

      response "200", "Workflow updated" do
        schema "$ref" => "#/components/schemas/AgentWorkflow"
        let(:workflow) { create(:agent_workflow) }
        let(:id)       { workflow.id }
        let(:payload)  { { agent_workflow: { name: "Renamed" } } }
        before { sign_in admin }
        run_test!
      end
    end

    delete "Delete a workflow (admin only)" do
      tags     "AI Agents"
      security [ Bearer: [] ]

      response "204", "Workflow deleted" do
        let(:workflow) { create(:agent_workflow) }
        let(:id)       { workflow.id }
        before { sign_in admin }
        run_test!
      end
    end
  end

  # ===========================================================================
  # TOGGLE — PATCH /api/v1/agent_workflows/:id/toggle
  # ===========================================================================
  path "/api/v1/agent_workflows/{id}/toggle" do
    parameter name: :id, in: :path, type: :integer

    patch "Toggle the active flag (admin only)" do
      tags     "AI Agents"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Toggled" do
        schema type: :object, properties: { id: { type: :integer }, active: { type: :boolean } }
        let(:workflow) { create(:agent_workflow, active: false) }
        let(:id)       { workflow.id }
        before { sign_in admin }
        run_test! do |response|
          expect(JSON.parse(response.body)["active"]).to be(true)
        end
      end
    end
  end

  # ===========================================================================
  # TRIGGER — POST /api/v1/agent_workflows/:id/trigger
  # ===========================================================================
  path "/api/v1/agent_workflows/{id}/trigger" do
    parameter name: :id, in: :path, type: :integer

    post "Manually trigger a workflow (admin only)" do
      tags     "AI Agents"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Trigger signal sent" do
        schema type: :object, properties: { message: { type: :string }, workflow_id: { type: :integer } }
        let(:workflow) { create(:agent_workflow, :manual) }
        let(:id)       { workflow.id }
        before { sign_in admin }
        run_test!
      end
    end
  end

  # ===========================================================================
  # EXECUTIONS — GET / POST /api/v1/agent_workflows/:id/executions
  # ===========================================================================
  path "/api/v1/agent_workflows/{id}/executions" do
    parameter name: :id, in: :path, type: :integer

    get "List execution history" do
      tags     "AI Agents"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Executions returned" do
        schema type: :object,
               properties: {
                 total:      { type: :integer },
                 page:       { type: :integer },
                 per_page:   { type: :integer },
                 executions: { type: :array, items: { type: :object } },
               }
        let(:workflow) { create(:agent_workflow) }
        let(:id)       { workflow.id }
        before do
          sign_in user
          create_list(:agent_execution, 3, agent_workflow: workflow)
        end
        run_test!
      end
    end

    post "Record an execution (AI Gateway, secret-authenticated)" do
      tags     "AI Agents"
      consumes "application/json"
      produces "application/json"
      description "Internal endpoint called by the AI Gateway with the X-Gateway-Secret header to log execution results."

      parameter name: "X-Gateway-Secret", in: :header, type: :string, required: true,
                description: "Shared secret for machine-to-machine auth from the AI Gateway."
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[agent_execution],
        properties: {
          agent_execution: {
            type: :object,
            properties: {
              status:       { type: :string, enum: AgentExecution::STATUSES },
              summary:      { type: :string },
              duration_ms:  { type: :integer },
              trigger_type: { type: :string },
            },
          },
        },
      }

      response "201", "Execution logged" do
        let(:workflow) { create(:agent_workflow) }
        let(:id)       { workflow.id }
        let(:payload)  { { agent_execution: { status: "success", summary: "Done", duration_ms: 1200 } } }
        let("X-Gateway-Secret") { "test-secret" }
        before do
          allow(ENV).to receive(:fetch).and_call_original
          allow(ENV).to receive(:fetch).with("GATEWAY_SECRET", nil).and_return("test-secret")
        end
        run_test!
      end

      response "401", "Missing/invalid gateway secret" do
        let(:workflow) { create(:agent_workflow) }
        let(:id)       { workflow.id }
        let(:payload)  { { agent_execution: { status: "success" } } }
        let("X-Gateway-Secret") { "wrong-secret" }
        run_test!
      end
    end
  end
end
