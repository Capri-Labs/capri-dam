require "swagger_helper"

RSpec.describe "Custom Node Definitions API", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  def json_body
    JSON.parse(response.body)
  end

  def manifest(overrides = {})
    {
      custom_node_definition: {
        key: "acme_watermark",
        name: "Acme Watermark",
        description: "Adds tenant-hosted watermarks.",
        icon: "water_drop",
        category: "custom",
        color: "#6366f1",
        config_schema: [ { key: "quality", type: "string", label: "Quality" } ],
        runtime: {
          endpoint_url: "https://plugins.example.com/workflow/custom-node",
          timeout_ms: 5000,
          outputs: [ "approved", "rejected" ],
          secret: "do-not-render",
        },
        status: "enabled",
      }.merge(overrides),
    }
  end

  path "/api/v1/custom_node_definitions" do
    get "List custom node definitions" do
      tags "Custom Nodes"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Definitions returned" do
        schema type: :object, properties: { items: { type: :array, items: { "$ref" => "#/components/schemas/CustomNodeDefinition" } } }
        run_test!
      end
    end

    post "Create a custom node definition (admin only)" do
      tags "Custom Nodes"
      consumes "application/json"
      produces "application/json"
      security [ Bearer: [] ]
      parameter name: :payload, in: :body, schema: { type: :object }

      response "201", "Definition created" do
        schema type: :object, properties: { custom_node_definition: { "$ref" => "#/components/schemas/CustomNodeDefinition" } }
        let(:payload) { manifest }
        run_test!
      end

      response "422", "Validation failed" do
        let(:payload) { manifest(key: "Bad-Key") }
        run_test!
      end
    end
  end

  path "/api/v1/custom_node_definitions/{id}" do
    parameter name: :id, in: :path, type: :integer

    get "Fetch a custom node definition" do
      tags "Custom Nodes"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Definition returned" do
        schema type: :object, properties: { custom_node_definition: { "$ref" => "#/components/schemas/CustomNodeDefinition" } }
        let(:id) { create(:custom_node_definition).id }
        run_test!
      end
    end

    patch "Update a custom node definition" do
      tags "Custom Nodes"
      consumes "application/json"
      produces "application/json"
      security [ Bearer: [] ]
      parameter name: :payload, in: :body, schema: { type: :object }

      response "200", "Definition updated" do
        let(:id) { create(:custom_node_definition).id }
        let(:payload) { { custom_node_definition: { name: "Renamed" } } }
        run_test!
      end
    end

    delete "Delete a custom node definition" do
      tags "Custom Nodes"
      security [ Bearer: [] ]

      response "204", "Definition deleted" do
        let(:id) { create(:custom_node_definition).id }
        run_test!
      end
    end
  end

  path "/api/v1/custom_node_definitions/{id}/enable" do
    parameter name: :id, in: :path, type: :integer

    post "Enable a custom node definition" do
      tags "Custom Nodes"
      security [ Bearer: [] ]

      response "200", "Definition enabled" do
        let(:id) { create(:custom_node_definition, :draft).id }
        run_test!
      end
    end
  end

  path "/api/v1/custom_node_definitions/{id}/disable" do
    parameter name: :id, in: :path, type: :integer

    post "Disable a custom node definition" do
      tags "Custom Nodes"
      security [ Bearer: [] ]

      response "200", "Definition disabled" do
        let(:id) { create(:custom_node_definition).id }
        run_test!
      end
    end
  end

  describe "runtime behavior" do
    before { sign_in admin }

    it "lists and shows definitions without secrets" do
      definition = create(:custom_node_definition)

      get "/api/v1/custom_node_definitions", as: :json
      expect(response).to have_http_status(:ok)
      item = json_body.fetch("items").first
      expect(item["node_type"]).to eq(definition.node_type)
      expect(item.dig("runtime", "secret")).to be_nil

      get "/api/v1/custom_node_definitions/#{definition.id}", as: :json
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("do-not-render")
      expect(json_body.dig("custom_node_definition", "runtime", "secret")).to be_nil
    end

    it "creates, updates, disables, enables, and destroys a definition" do
      post "/api/v1/custom_node_definitions", params: manifest, as: :json
      expect(response).to have_http_status(:created)
      definition = CustomNodeDefinition.find_by!(key: "acme_watermark")
      expect(json_body.dig("custom_node_definition", "node_type")).to eq("plugin:acme_watermark")
      expect(json_body.dig("custom_node_definition", "runtime", "secret")).to be_nil

      patch "/api/v1/custom_node_definitions/#{definition.id}", params: { custom_node_definition: { name: "Renamed" } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(definition.reload.name).to eq("Renamed")

      post "/api/v1/custom_node_definitions/#{definition.id}/disable", as: :json
      expect(response).to have_http_status(:ok)
      expect(definition.reload).to be_disabled

      post "/api/v1/custom_node_definitions/#{definition.id}/enable", as: :json
      expect(response).to have_http_status(:ok)
      expect(definition.reload).to be_enabled

      delete "/api/v1/custom_node_definitions/#{definition.id}", as: :json
      expect(response).to have_http_status(:no_content)
      expect(CustomNodeDefinition.exists?(definition.id)).to be(false)
    end

    it "returns validation errors" do
      post "/api/v1/custom_node_definitions", params: manifest(key: "Bad-Key"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_body["errors"]).to be_present
    end

    it "enforces admin access" do
      sign_out admin
      sign_in user

      get "/api/v1/custom_node_definitions", as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
