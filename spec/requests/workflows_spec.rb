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
                   status: { type: :string, enum: [ 'active', 'inactive', 'draft' ] },
                   trigger_type: { type: :string, enum: [ 'on_ingest', 'manual' ] },
                   graph_data: { type: :object, description: 'React Flow canvas JSON', nullable: true },
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
              graph_data: {
                type: :object,
                properties: {
                  nodes: { type: :array, items: { type: :object } },
                  edges: { type: :array, items: { type: :object } },
                  viewport: { type: :object },
                },
              },
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
        let(:payload) { { workflow: { name: 'Approval Flow', trigger_type: 'manual' } } }
        run_test!
      end

      response '422', 'validation failed' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 errors: { type: :array, items: { type: :string } },
               }
        let(:payload) { { workflow: { name: '', trigger_type: 'manual' } } }
        run_test!
      end
    end
  end

  path '/workflows/{id}' do
    parameter name: :id, in: :path, type: :integer, description: 'Workflow ID'

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
                 graph_data: { type: :object, nullable: true },
                 workflow_steps: { type: :array, items: { type: :object } },
               }
        let(:workflow) { FactoryBot.create(:workflow) }
        let(:id)       { workflow.id }
        run_test!
      end

      response '404', 'workflow not found' do
        schema type: :object, properties: { error: { type: :string } }
        let(:id) { 0 }
        run_test!
      end
    end

    # 4. PATCH /workflows/:id
    patch 'Updates an existing workflow definition' do
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
        let(:workflow) { FactoryBot.create(:workflow) }
        let(:id)       { workflow.id }
        let(:payload)  { { workflow: { name: 'Renamed Approval Flow' } } }
        run_test!
      end

      response '422', 'update failed — validation error' do
        schema type: :object, properties: { success: { type: :boolean }, errors: { type: :array, items: { type: :string } } }
        let(:workflow) { FactoryBot.create(:workflow) }
        let(:id)       { workflow.id }
        let(:payload)  { { workflow: { name: '' } } }
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
        let(:workflow) { FactoryBot.create(:workflow) }
        let(:id)       { workflow.id }
        run_test!
      end

      response '422', 'deletion failed' do
        schema type: :object, properties: { success: { type: :boolean }, errors: { type: :array, items: { type: :string } } }
        let(:workflow) { FactoryBot.create(:workflow) }
        let(:id)       { workflow.id }
        before { allow_any_instance_of(Workflow).to receive(:destroy).and_return(false) } # rubocop:disable RSpec/AnyInstance
        run_test!
      end
    end
  end

  path '/workflows/{id}/toggle_status' do
    parameter name: :id, in: :path, type: :integer, description: 'Workflow ID'

    # 6. PATCH /workflows/:id/toggle_status
    patch 'Activates or deactivates a workflow definition' do
      tags 'Workflow Definitions'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'status toggled successfully' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 status: { type: :string, enum: [ 'active', 'inactive', 'draft' ] },
               }
        # Create an active workflow with a step, then toggle to inactive.
        # Toggling inactive→active would trigger `must_have_steps` validation;
        # toggling active→inactive does not, so no steps are required for the
        # success path.
        let(:step)     { FactoryBot.build(:workflow_step) }
        let(:workflow) { FactoryBot.create(:workflow, status: :active, workflow_steps: [ step ]) }
        let(:id)       { workflow.id }
        run_test!
      end

      response '422', 'toggle failed — could not save' do
        schema type: :object, properties: { success: { type: :boolean }, errors: { type: :array, items: { type: :string } } }
        let(:workflow) { FactoryBot.create(:workflow) }
        let(:id)       { workflow.id }
        before { allow_any_instance_of(Workflow).to receive(:update).and_return(false) } # rubocop:disable RSpec/AnyInstance
        run_test!
      end
    end
  end
end
