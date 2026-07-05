# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Workflow HTML controller coverage', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /workflows' do
    it 'renders the HTML shell with serialized workflows for React' do
      modifier = create(:user, first_name: 'Ada', last_name: 'Lovelace')
      workflow = create(:workflow, name: 'Shell Flow', updated_by_id: modifier.id, status: :draft)
      create(:workflow_step, workflow: workflow, assignee_type: 'user', assignee_id: user.id)

      get '/workflows'

      expect(response).to have_http_status(:ok)
      expect(assigns(:active_view)).to eq('Workflows')
      expect(response.body).to include('data-active-view="Workflows"')
      workflows_json = JSON.parse(assigns(:workflows_json))
      expect(workflows_json).to contain_exactly(hash_including(
        'id' => workflow.id,
        'name' => 'Shell Flow',
        'status' => 'draft',
        'trigger_type' => 'manual',
        'step_count' => 1,
        'last_modified_by' => 'Ada Lovelace'
      ))
      pagination_json = JSON.parse(assigns(:workflows_pagination_json))
      expect(pagination_json).to include('page' => 1, 'per_page' => 25, 'total' => 1, 'total_pages' => 1)
      expect(response.body).to include('data-workflows-pagination=')
    end

    it 'falls back to an empty JSON array and default modifier name' do
      workflow = create(:workflow, name: 'Fallback Flow', updated_by_id: nil)

      get '/workflows'

      workflows_json = JSON.parse(assigns(:workflows_json))
      expect(workflows_json).to include(hash_including(
        'id' => workflow.id,
        'last_modified_by' => 'Admin'
      ))

      Workflow.delete_all
      get '/workflows'
      expect(assigns(:workflows_json)).to eq('[]')
    end

    it 'returns workflows with steps as JSON' do
      workflow = create(:workflow, name: 'JSON Flow')
      step = create(:workflow_step, workflow: workflow, title: 'Approve', assignee_type: 'user', assignee_id: user.id)

      get '/workflows.json'

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to contain_exactly(hash_including(
        'id' => workflow.id,
        'name' => 'JSON Flow',
        'workflow_steps' => include(hash_including('id' => step.id, 'title' => 'Approve'))
      ))
    end

    it 'paginates the JSON response when a page param is given' do
      30.times { |i| create(:workflow, name: "Bulk Flow #{i}") }

      get '/workflows.json', params: { page: 2 }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['workflows'].length).to eq(5) # 30 total, 25 per page => 5 remaining
      expect(body['pagination']).to include('page' => 2, 'per_page' => 25, 'total' => 30, 'total_pages' => 2)
    end
  end

  describe 'GET /workflows/dashboard' do
    it 'renders the dashboard page and highlights "My Tasks" in the sidebar' do
      get '/workflows/dashboard'

      expect(response).to have_http_status(:ok)
      expect(assigns(:active_view)).to eq('My Tasks')
      expect(response.body).to include('data-active-view="My Tasks"')
    end
  end

  describe 'GET /workflows/:id.json' do
    it 'returns the workflow with its steps' do
      workflow = create(:workflow, name: 'Shown Flow')
      step = create(:workflow_step, workflow: workflow, title: 'Shown Step', assignee_type: 'user', assignee_id: user.id)

      get "/workflows/#{workflow.id}.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'id' => workflow.id,
        'name' => 'Shown Flow',
        'workflow_steps' => include(hash_including('id' => step.id, 'title' => 'Shown Step'))
      )
    end

    it 'returns a not found JSON response when the workflow is missing' do
      get '/workflows/0.json'

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to include("Couldn't find Workflow")
    end
  end

  describe 'POST /workflows' do
    it 'stores creator fields and deeply nested graph data' do
      params = {
        workflow: {
          name: 'Graph Flow',
          trigger_type: 'manual',
          graph_data: {
            nodes: [ { id: 'n1', data: { label: 'Start' } } ],
            edges: [],
            viewport: { x: 1, y: 2, zoom: 0.5 },
          },
        },
      }

      post '/workflows', params: params

      expect(response).to have_http_status(:created)
      workflow = Workflow.last
      expect(workflow.creator).to eq(user)
      expect(workflow.last_modifier).to eq(user)
      expect(workflow.graph_data).to include('nodes' => [ hash_including('id' => 'n1') ])
    end

    it 'returns validation errors for invalid workflows' do
      post '/workflows', params: { workflow: { name: '', trigger_type: 'manual' } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('success' => false)
      expect(response.parsed_body['errors']).not_to be_empty
    end
  end

  describe 'PATCH /workflows/:id' do
    it 'updates nested steps and last modifier' do
      workflow = create(:workflow)
      step = create(:workflow_step, workflow: workflow, title: 'Old', assignee_type: 'user', assignee_id: user.id)

      patch "/workflows/#{workflow.id}", params: {
        workflow: {
          workflow_steps_attributes: [ { id: step.id, title: 'New', position: 2 } ],
        },
      }

      expect(response).to have_http_status(:ok)
      expect(step.reload).to have_attributes(title: 'New', position: 2)
      expect(workflow.reload.last_modifier).to eq(user)
    end

    it 'destroys a step that still has workflow tasks without a foreign key error' do
      workflow = create(:workflow)
      step = create(:workflow_step, workflow: workflow, assignee_type: 'user', assignee_id: user.id)
      instance = create(:workflow_instance, workflow: workflow)
      create(:workflow_task, workflow_step: step, workflow_instance: instance, user: user)

      patch "/workflows/#{workflow.id}", params: {
        workflow: {
          workflow_steps_attributes: [ { id: step.id, _destroy: true } ],
        },
      }

      expect(response).to have_http_status(:ok)
      expect(WorkflowStep.where(id: step.id)).to be_empty
      expect(WorkflowTask.where(workflow_step_id: step.id)).to be_empty
    end

    it 'returns validation errors when the update is invalid' do
      workflow = create(:workflow, name: 'Rename Me')

      patch "/workflows/#{workflow.id}", params: { workflow: { name: '' } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('success' => false)
      expect(response.parsed_body['errors']).not_to be_empty
    end
  end

  describe 'DELETE /workflows/:id' do
    it 'deletes workflows successfully' do
      workflow = create(:workflow, name: 'Delete Me')

      delete "/workflows/#{workflow.id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('success' => true, 'message' => 'Workflow deleted')
      expect(Workflow.exists?(workflow.id)).to be(false)
    end

    it 'returns an error when deletion fails' do
      workflow = create(:workflow)
      allow_any_instance_of(Workflow).to receive(:destroy).and_return(false) # rubocop:disable RSpec/AnyInstance

      delete "/workflows/#{workflow.id}"

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('success' => false, 'errors' => [ 'Could not delete workflow' ])
    end
  end

  describe 'PATCH /workflows/:id/toggle_status' do
    it 'activates an inactive workflow when validation passes' do
      workflow = create(:workflow, status: :inactive)
      create(:workflow_step, workflow: workflow, assignee_type: 'user', assignee_id: user.id)

      patch "/workflows/#{workflow.id}/toggle_status"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('success' => true, 'status' => 'active')
      expect(workflow.reload.last_modifier).to eq(user)
    end

    it 'deactivates an active workflow when validation passes' do
      workflow = create(:workflow, status: :inactive)
      create(:workflow_step, workflow: workflow, assignee_type: 'user', assignee_id: user.id)
      workflow.update_column(:status, 'active')

      patch "/workflows/#{workflow.id}/toggle_status"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('success' => true, 'status' => 'inactive')
      expect(workflow.reload.last_modifier).to eq(user)
    end

    it 'returns validation errors when the status change cannot be saved' do
      workflow = create(:workflow, status: :inactive)
      allow_any_instance_of(Workflow).to receive(:update).and_return(false) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Workflow).to receive(:errors).and_return(instance_double(ActiveModel::Errors, full_messages: [ 'Toggle failed' ])) # rubocop:disable RSpec/AnyInstance

      patch "/workflows/#{workflow.id}/toggle_status"

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('success' => false)
      expect(response.parsed_body['errors']).to eq([ 'Toggle failed' ])
    end
  end

  describe 'authentication' do
    it 'redirects signed-out users' do
      sign_out user

      get '/workflows'

      expect(response).to have_http_status(:found)
    end
  end
end
