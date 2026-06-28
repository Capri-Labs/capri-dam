# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Api::V1::AiModelConfigs", type: :request do
  # ===========================================================================
  # LIST — GET /api/v1/ai_model_configs
  # ===========================================================================
  path "/api/v1/ai_model_configs" do
    get "List AI model configs" do
      tags "Style & Model Hub"
      produces "application/json"
      security [ Bearer: [] ]
      description "Returns all registered AI model endpoint configurations. Admin only."
      parameter name: :capability, in: :query, type: :string, required: false,
                description: "Filter by capability: embedding | generation | vision | style_transfer | audio"
      parameter name: :enabled, in: :query, type: :boolean, required: false,
                description: "Filter by enabled state"

      response "200", "List of AI model configs" do
        schema type: :object,
               properties: {
                 total:   { type: :integer },
                 configs: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:                   { type: :integer },
                       name:                 { type: :string },
                       provider:             { type: :string, example: "openai" },
                       model_id:             { type: :string, example: "gpt-4o" },
                       capability:           { type: :string, example: "generation" },
                       enabled:              { type: :boolean },
                       is_default:           { type: :boolean },
                       health_status:        { type: :string, example: "healthy" },
                       health_latency_ms:    { type: :integer, nullable: true },
                       last_health_check_at: { type: :string, format: "date-time", nullable: true },
                       created_at:           { type: :string, format: "date-time" },
                       updated_at:           { type: :string, format: "date-time" },
                     },
                   },
                 },
               }
        run_test!
      end

      response "401", "Unauthenticated" do
        run_test!
      end

      response "403", "Forbidden (admin only)" do
        run_test!
      end
    end

    post "Create an AI model config" do
      tags "Style & Model Hub"
      consumes "application/json"
      produces "application/json"
      security [ Bearer: [] ]
      description "Registers a new AI model endpoint. Admin only. Broadcasts model.config.updated to the gateway on save."

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ "ai_model_config" ],
        properties: {
          ai_model_config: {
            type: :object,
            required: [ "name", "provider", "model_id", "capability" ],
            properties: {
              name:         { type: :string, example: "GPT-4o Vision" },
              provider:     { type: :string, example: "openai",
                              description: "openai | anthropic | ollama | huggingface | azure_openai | custom" },
              model_id:     { type: :string, example: "gpt-4o" },
              capability:   { type: :string, example: "generation",
                              description: "embedding | generation | vision | style_transfer | audio" },
              enabled:      { type: :boolean, example: true },
              config_params: { type: :object, example: {} },
            },
          },
        },
      }

      response "201", "Model config created" do
        run_test!
      end

      response "422", "Validation error" do
        run_test!
      end
    end
  end

  # ===========================================================================
  # CAPABILITIES — GET /api/v1/ai_model_configs/capabilities
  # ===========================================================================
  path "/api/v1/ai_model_configs/capabilities" do
    get "List capabilities, providers, and health statuses" do
      tags "Style & Model Hub"
      produces "application/json"
      security [ Bearer: [] ]
      description "Returns valid enum values for AI model config fields. Used to populate the Model Hub form."

      response "200", "Enum values" do
        schema type: :object,
               properties: {
                 capabilities:    { type: :array, items: { type: :string } },
                 providers:       { type: :array, items: { type: :string } },
                 health_statuses: { type: :array, items: { type: :string } },
               }
        run_test!
      end
    end
  end

  # ===========================================================================
  # SHOW / UPDATE / DELETE — /api/v1/ai_model_configs/:id
  # ===========================================================================
  path "/api/v1/ai_model_configs/{id}" do
    parameter name: :id, in: :path, type: :integer, required: true, description: "AI model config ID"

    get "Fetch a single AI model config" do
      tags "Style & Model Hub"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Model config found" do
        run_test!
      end

      response "404", "Not found" do
        run_test!
      end
    end

    patch "Update an AI model config" do
      tags "Style & Model Hub"
      consumes "application/json"
      produces "application/json"
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          ai_model_config: {
            type: :object,
            properties: {
              name:         { type: :string },
              enabled:      { type: :boolean },
              config_params: { type: :object },
            },
          },
        },
      }

      response "200", "Updated" do
        run_test!
      end
    end

    delete "Delete an AI model config" do
      tags "Style & Model Hub"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Deleted" do
        run_test!
      end
    end
  end

  # ===========================================================================
  # HEALTH CHECK — POST /api/v1/ai_model_configs/:id/health_check
  # ===========================================================================
  path "/api/v1/ai_model_configs/{id}/health_check" do
    parameter name: :id, in: :path, type: :integer, required: true

    post "Queue a gateway health-check ping" do
      tags "Style & Model Hub"
      produces "application/json"
      security [ Bearer: [] ]
      description "Enqueues AiModelHealthCheckWorker to ping the gateway and report back health status."

      response "200", "Health check queued" do
        run_test!
      end
    end
  end

  # ===========================================================================
  # SET DEFAULT — POST /api/v1/ai_model_configs/:id/set_default
  # ===========================================================================
  path "/api/v1/ai_model_configs/{id}/set_default" do
    parameter name: :id, in: :path, type: :integer, required: true

    post "Promote model to default for its capability" do
      tags "Style & Model Hub"
      produces "application/json"
      security [ Bearer: [] ]
      description "Sets is_default=true for this config and demotes the previous default for the same capability."

      response "200", "Default updated" do
        run_test!
      end
    end
  end

  # ===========================================================================
  # HEALTH CALLBACK — POST /api/v1/ai_model_configs/:id/health_callback
  # ===========================================================================
  path "/api/v1/ai_model_configs/{id}/health_callback" do
    parameter name: :id, in: :path, type: :integer, required: true

    post "Receive health status from AI Gateway (M2M)" do
      tags "Style & Model Hub"
      consumes "application/json"
      produces "application/json"
      security [ GatewaySecret: [] ]
      description "Called by the AI Gateway after a health-check ping. Authenticated by X-Gateway-Secret header."

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          health: {
            type: :object,
            properties: {
              health_status:    { type: :string, example: "healthy",
                                  description: "healthy | degraded | unhealthy | unknown" },
              health_latency_ms: { type: :integer, example: 95 },
              error_message:    { type: :string, nullable: true },
            },
          },
        },
      }

      response "200", "Health status recorded" do
        run_test!
      end

      response "401", "Invalid or missing gateway secret" do
        run_test!
      end
    end
  end
end
