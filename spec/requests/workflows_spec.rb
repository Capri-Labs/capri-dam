require 'swagger_helper'

RSpec.describe 'Workflows', type: :request do
  path '/workflows' do
    # 1. GET /workflows (Format JSON only)
    get 'Retrieves a list of all workflow definitions' do
      tags 'Workflow Definitions'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'workflows retrieved successfully' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id: { type: :integer },
                   name: { type: :string },
                   description: { type: :string, nullable: true },
                   status: { type: :string, enum: [ 'active', 'inactive' ] },
                   trigger_type: { type: :string, enum: [ 'on_ingest', 'manual' ] },
                   graph_data: { type: :object, description: 'Deeply nested React Flow JSON structure' },
                   workflow_steps: {
                     type: :array,
                     items: {
                       type: :object,
                       properties: {
                         id: { type: :integer },
                         title: { type: :string },
                         position: { type: :integer },
                         step_type: { type: :string },
                         assignee_type: { type: :string },
                       },
                     },
                   },
                 },
               }
        run_test!
      end
    end

    # 2. POST /workflows
    post 'Creates a new workflow definition' do
      tags 'Workflow Definitions'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          workflow: {
            type: :object,
            properties: {
              name: { type: :string, example: 'Product Shot Approval' },
              description: { type: :string, example: 'Legal and Art review for new products' },
              trigger_type: { type: :string, enum: [ 'on_ingest', 'manual' ], example: 'on_ingest' },

              #  CRITICAL: Documenting the nested graph data from React Flow
              graph_data: {
                type: :object,
                properties: {
                  nodes: { type: :array, items: { type: :object } },
                  edges: { type: :array, items: { type: :object } },
                  viewport: { type: :object },
                },
              },

              #  CRITICAL: Documenting standard Rails nested attributes
              workflow_steps_attributes: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    title: { type: :string, example: 'Legal Review' },
                    position: { type: :integer, example: 1 },
                    step_type: { type: :string, enum: [ 'approval', 'task' ], example: 'approval' },
                    assignee_type: { type: :string, enum: [ 'user', 'group' ], example: 'group' },
                    assignee_id: { type: :integer, example: 5 },
                  },
                  required: [ 'title', 'position', 'step_type', 'assignee_type', 'assignee_id' ],
                },
              },
            },
            required: [ 'name', 'trigger_type' ],
          },
        },
        required: [ 'workflow' ],
      }

      response '201', 'workflow created successfully' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 workflow: { type: :object },
               }
        run_test!
      end

      response '422', 'validation failed' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 errors: { type: :array, items: { type: :string } },
               }
        run_test!
      end
    end
  end

  path '/workflows/{id}' do
    parameter name: :id, in: :path, type: :string, description: 'Workflow ID'

    # 3. GET /workflows/:id.json
    get 'Retrieves details of a specific workflow definition' do
      tags 'Workflow Definitions'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'workflow details retrieved' do
        schema type: :object,
               properties: {
                 id: { type: :integer },
                 name: { type: :string },
                 graph_data: { type: :object },
                 workflow_steps: { type: :array, items: { type: :object } },
               }
        run_test!
      end
    end

    # 4. PATCH /workflows/:id
    patch 'Updates an existing workflow definition' do
      tags 'Workflow Definitions'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      # Payload structure is the same as POST, adding :_destroy for steps
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          workflow: {
            type: :object,
            properties: {
              name: { type: :string },
              description: { type: :string },
              graph_data: { type: :object },
              workflow_steps_attributes: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    id: { type: :integer, description: 'Existing step ID for updates' },
                    title: { type: :string },
                    _destroy: { type: :boolean, description: 'Mark for deletion' },
                  },
                },
              },
            },
          },
        },
      }

      response '200', 'workflow updated successfully' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 workflow: { type: :object, properties: { workflow_steps: { type: :array, items: { type: :object } } } },
               }
        run_test!
      end

      response '422', 'update failed' do
        schema type: :object, properties: { success: { type: :boolean }, errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end

    # 5. DELETE /workflows/:id
    delete 'Deletes a workflow definition' do
      tags 'Workflow Definitions'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'workflow deleted' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end

      response '408', 'deletion failed (using search_timeout status)' do
        # Note: Controller oddly returns 408 Search Timeout on failure
        schema type: :object, properties: { success: { type: :boolean }, errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end

  path '/workflows/{id}/toggle_status' do
    parameter name: :id, in: :path, type: :string, description: 'Workflow ID'

    # 6. PATCH /workflows/:id/toggle_status
    patch 'Activates or deactivates a workflow definition' do
      tags 'Workflow Definitions'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'status toggled successfully' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 status: { type: :string, enum: [ 'active', 'inactive' ] },
               }
        run_test!
      end

      response '200', 'toggle failed' do
        schema type: :object, properties: { success: { type: :boolean } }
        run_test!
      end
    end
  end
end
