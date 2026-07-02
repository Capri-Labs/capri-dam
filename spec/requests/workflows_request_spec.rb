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
      workflows_json = JSON.parse(assigns(:workflows_json))
      expect(workflows_json).to contain_exactly(hash_including(
        'id' => workflow.id,
        'name' => 'Shell Flow',
        'status' => 'draft',
        'trigger_type' => 'manual',
        'step_count' => 1,
        'last_modified_by' => 'Ada Lovelace'
      ))
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
  end

  describe 'GET /workflows/dashboard' do
    it 'renders the dashboard page' do
      get '/workflows/dashboard'

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /workflows/:id.json' do
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
  end

  describe 'authentication' do
    it 'redirects signed-out users' do
      sign_out user

      get '/workflows'

      expect(response).to have_http_status(:found)
    end
  end
end
