require 'swagger_helper'

# Behavioural + documentation specs for the Workflow Instances admin API.
RSpec.describe 'Api::V1::WorkflowInstances', type: :request do
  # ── Swagger documentation scaffolds (excluded from default run) ──────────────
  path '/api/v1/workflow_instances/{id}/force_cancel' do
    parameter name: :id, in: :path, type: :string, description: 'Workflow Instance ID'

    post 'Force-cancels a running workflow instance (admin only)' do
      tags 'Workflows & Tasks'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: { reason: { type: :string, example: 'Asset withdrawn from campaign' } },
      }

      response '200', 'instance cancelled' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end
    end
  end

  path '/api/v1/workflow_instances/{id}' do
    parameter name: :id, in: :path, type: :string, description: 'Workflow Instance ID'

    delete 'Deletes a terminal workflow instance (admin only)' do
      tags 'Workflows & Tasks'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'instance deleted' do
        schema type: :object, properties: { message: { type: :string } }
        run_test!
      end
    end
  end

  # ── Behavioural specs (run in the default suite) ─────────────────────────────
  describe 'admin operations', :aggregate_failures do
    let(:admin)    { create(:user, admin: true) }
    let(:member)   { create(:user) }
    let(:asset)    { create(:asset) }
    let(:workflow) { create(:workflow) }
    let(:instance) do
      create(:workflow_instance, asset: asset, workflow: workflow, status: 'in_progress', started_at: Time.current)
    end

    describe 'POST /api/v1/workflow_instances/:id/force_cancel' do
      it 'cancels a running instance and records the reason' do
        sign_in admin
        post "/api/v1/workflow_instances/#{instance.id}/force_cancel",
             params: { reason: 'Withdrawn' }.to_json,
             headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:ok)
        instance.reload
        expect(instance.status).to eq('canceled')
        expect(instance.cancel_reason).to eq('Withdrawn')
        expect(instance.cancelled_by).to eq(admin)
      end

      it 'rejects non-admins with 403' do
        sign_in member
        post "/api/v1/workflow_instances/#{instance.id}/force_cancel",
             params: {}.to_json, headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:forbidden)
        expect(instance.reload.status).to eq('in_progress')
      end

      it 'returns 422 when the instance is already terminal' do
        instance.update!(status: 'completed', completed_at: Time.current)
        sign_in admin
        post "/api/v1/workflow_instances/#{instance.id}/force_cancel",
             params: {}.to_json, headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe 'DELETE /api/v1/workflow_instances/:id' do
      it 'deletes a terminal instance' do
        instance.update!(status: 'completed', completed_at: Time.current)
        sign_in admin
        expect do
          delete "/api/v1/workflow_instances/#{instance.id}"
        end.to change(WorkflowInstance, :count).by(-1)
        expect(response).to have_http_status(:ok)
      end

      it 'refuses to delete a running instance' do
        sign_in admin
        delete "/api/v1/workflow_instances/#{instance.id}"
        expect(response).to have_http_status(:unprocessable_entity)
        expect(WorkflowInstance.exists?(instance.id)).to be(true)
      end
    end

    describe 'POST /api/v1/workflows/bulk_stop' do
      it 'cancels every selected running instance' do
        other = create(:workflow_instance, asset: asset, workflow: workflow, status: 'in_progress')
        sign_in admin
        post '/api/v1/workflows/bulk_stop',
             params: { ids: [ instance.id, other.id ] }.to_json,
             headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:ok)
        expect(instance.reload.status).to eq('canceled')
        expect(other.reload.status).to eq('canceled')
      end
    end
  end
end
