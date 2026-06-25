require 'swagger_helper'

RSpec.describe 'Api::V1::WorkflowTasks', type: :request do
  # --- WORKFLOW TASK SUBMISSION ---
  path '/api/v1/workflow_tasks/{id}/submit' do
    parameter name: :id, in: :path, type: :string, description: 'Workflow Task ID'

    post 'Submits a decision for a pending workflow task' do
      tags 'Workflows & Tasks'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          decision: { type: :string, enum: [ 'approved', 'rejected' ], example: 'approved' },
          comment: { type: :string, example: 'Looks good to go. Assets are on brand.' },
        },
        required: [ 'decision' ],
      }

      response '200', 'decision recorded successfully' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end

      response '403', 'forbidden (user not assigned to this task)' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '422', 'unprocessable entity (task already completed or canceled)' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # --- WORKFLOW DASHBOARD & BULK ACTIONS ---
  path '/api/v1/workflows/bulk_stop' do
    post 'Admin action to forcibly cancel multiple workflow instances' do
      tags 'Workflows & Tasks'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          ids: {
            type: :array,
            items: { type: :integer },
            example: [ 101, 102, 105 ],
            description: 'Array of Workflow Instance IDs to cancel',
          },
        },
        required: [ 'ids' ],
      }

      response '200', 'workflows canceled successfully' do
        schema type: :object, properties: { success: { type: :boolean } }
        run_test!
      end
    end
  end

  path '/api/v1/workflows/dashboard' do
    get 'Retrieves workflow data for the user dashboard' do
      tags 'Workflows & Tasks'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'dashboard data retrieved successfully' do
        schema type: :object,
               properties: {
                 my_tasks: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       task_id: { type: :integer },
                       step_title: { type: :string },
                       asset_id: { type: :integer },
                       asset_name: { type: :string },
                       asset_thumb: { type: :string, nullable: true },
                       assigned_at: { type: :string, format: 'date-time' },
                     },
                   },
                 },
                 active_workflows: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       instance_id: { type: :integer },
                       workflow_name: { type: :string },
                       current_step: { type: :string },
                       asset_id: { type: :integer },
                       asset_name: { type: :string },
                       started_at: { type: :string, format: 'date-time' },
                     },
                   },
                 },
                 completed_workflows: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       instance_id: { type: :integer },
                       workflow_name: { type: :string },
                       asset_id: { type: :integer },
                       asset_name: { type: :string },
                       status: { type: :string },
                       completed_at: { type: :string, format: 'date-time' },
                     },
                   },
                 },
               }
        run_test!
      end
    end
  end
end
