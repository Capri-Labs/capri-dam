# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API workflow instance coverage', type: :request do
  let(:user) { create(:user) }
  let(:admin) { create(:user, admin: true) }
  let(:asset) { create(:asset, title: 'Campaign Hero') }
  let(:workflow) { create(:workflow, name: 'Launch Review') }
  let(:step) do
    create(:workflow_step, workflow: workflow, title: 'Legal Review', assignee_type: 'user', assignee_id: user.id)
  end
  let(:instance) do
    create(:workflow_instance,
           asset: asset,
           workflow: workflow,
           current_step: step,
           status: 'in_progress',
           started_at: 2.hours.ago)
  end

  before { sign_in admin }

  describe 'GET /api/v1/workflow_instances' do
    it 'filters by status and workflow and serializes cancellation metadata' do
      instance.update!(status: 'canceled', completed_at: Time.current, cancelled_by: admin, cancel_reason: 'duplicate')
      create(:workflow_instance, status: 'in_progress')

      get '/api/v1/workflow_instances', params: { status: 'canceled', workflow_id: workflow.id }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['total']).to eq(2)
      expect(body['instances'].size).to eq(1)
      expect(body['instances'].first).to include(
        'id' => instance.id,
        'workflow_name' => 'Launch Review',
        'asset_name' => 'Campaign Hero',
        'current_step' => 'Legal Review',
        'cancel_reason' => 'duplicate',
        'cancelled_by' => admin.email,
        'terminal' => true
      )
    end
  end

  describe 'GET /api/v1/workflow_instances/:id' do
    it 'includes tasks and audit log in the detail response' do
      task = create(:workflow_task, workflow_instance: instance, workflow_step: step, user: user, comment: 'ready')
      instance.update!(audit_log: [ { action: 'started' } ])

      get "/api/v1/workflow_instances/#{instance.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['tasks']).to contain_exactly(hash_including(
        'id' => task.id,
        'step_name' => 'Legal Review',
        'user_email' => user.email,
        'status' => 'pending',
        'comment' => 'ready'
      ))
      expect(body['audit_log']).to eq([ { 'action' => 'started' } ])
    end

    it 'returns not found for a missing instance' do
      get '/api/v1/workflow_instances/0'

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('Workflow instance not found.')
    end
  end

  describe 'POST /api/v1/workflows/bulk_reassign' do
    it 'requires a target user or group' do
      post '/api/v1/workflows/bulk_reassign', params: { ids: [ instance.id ] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Provide user_id or group_id for reassignment.')
    end

    it 'reassigns pending tasks to a user and notifies the first task' do
      replacement = create(:user)
      task = create(:workflow_task, workflow_instance: instance, workflow_step: step, user: user)
      allow(TaskNotificationWorker).to receive(:perform_async)

      post '/api/v1/workflows/bulk_reassign', params: { ids: [ instance.id ], user_id: replacement.id }

      expect(response).to have_http_status(:ok)
      expect(task.reload.user).to eq(replacement)
      expect(TaskNotificationWorker).to have_received(:perform_async).with(task.id)
      expect(response.parsed_body['message']).to eq('1 instance(s) reassigned.')
    end

    it 'replaces pending tasks with one task per group member' do
      member_a = create(:user)
      member_b = create(:user)
      group = create(:user_group)
      group.users << [ member_a, member_b ]
      create(:workflow_task, workflow_instance: instance, workflow_step: step, user: user)
      allow(TaskNotificationWorker).to receive(:perform_async)

      post '/api/v1/workflows/bulk_reassign', params: { ids: [ instance.id ], group_id: group.id }

      expect(response).to have_http_status(:ok)
      expect(instance.workflow_tasks.reload.map(&:user)).to contain_exactly(member_a, member_b)
      expect(TaskNotificationWorker).to have_received(:perform_async).twice
    end

    it 'skips invalid user and group targets without changing tasks' do
      task = create(:workflow_task, workflow_instance: instance, workflow_step: step, user: user)
      allow(TaskNotificationWorker).to receive(:perform_async)

      post '/api/v1/workflows/bulk_reassign', params: { ids: [ instance.id ], user_id: 0, group_id: 0 }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['message']).to eq('0 instance(s) reassigned.')
      expect(task.reload.user).to eq(user)
      expect(TaskNotificationWorker).not_to have_received(:perform_async)
    end
  end

  describe 'POST /api/v1/workflows/bulk_trigger' do
    let(:active_workflow) { create(:workflow, name: 'Brand Review', status: 'draft') }
    let!(:step_for_active) do
      create(:workflow_step, workflow: active_workflow, title: 'Review', assignee_type: 'user', assignee_id: user.id)
    end

    before { active_workflow.update!(status: 'active') }

    it 'rejects an unknown or inactive workflow id' do
      post '/api/v1/workflows/bulk_trigger', params: { workflow_id: workflow.id, asset_ids: [ asset.id ] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Workflow not found or inactive.')
    end

    it 'requires at least one asset or folder to be selected' do
      post '/api/v1/workflows/bulk_trigger', params: { workflow_id: active_workflow.id }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Select at least one asset or folder.')
    end

    it 'queues the workflow for directly selected assets' do
      allow(WorkflowInitiatorWorker).to receive(:perform_async)

      post '/api/v1/workflows/bulk_trigger', params: { workflow_id: active_workflow.id, asset_ids: [ asset.id ] }

      expect(response).to have_http_status(:accepted)
      expect(WorkflowInitiatorWorker).to have_received(:perform_async).with(asset.id, active_workflow.id)
      expect(response.parsed_body).to include('queued' => 1, 'workflow_id' => active_workflow.id)
    end

    it 'expands selected folders into every active asset inside them, recursively' do
      root  = create(:folder, user: user)
      child = create(:folder, user: user, parent: root)
      asset_in_root  = create(:asset, folder: root)
      asset_in_child = create(:asset, folder: child)
      trashed_asset  = create(:asset, folder: child, deleted_at: Time.current)
      allow(WorkflowInitiatorWorker).to receive(:perform_async)

      post '/api/v1/workflows/bulk_trigger', params: { workflow_id: active_workflow.id, folder_ids: [ root.id ] }

      expect(response).to have_http_status(:accepted)
      expect(WorkflowInitiatorWorker).to have_received(:perform_async).with(asset_in_root.id, active_workflow.id)
      expect(WorkflowInitiatorWorker).to have_received(:perform_async).with(asset_in_child.id, active_workflow.id)
      expect(WorkflowInitiatorWorker).not_to have_received(:perform_async).with(trashed_asset.id, anything)
      expect(response.parsed_body['queued']).to eq(2)
    end

    it 'de-duplicates assets that are selected both directly and via a folder' do
      folder = create(:folder, user: user)
      shared_asset = create(:asset, folder: folder)
      allow(WorkflowInitiatorWorker).to receive(:perform_async)

      post '/api/v1/workflows/bulk_trigger',
           params: { workflow_id: active_workflow.id, asset_ids: [ shared_asset.id ], folder_ids: [ folder.id ] }

      expect(response).to have_http_status(:accepted)
      expect(WorkflowInitiatorWorker).to have_received(:perform_async).once.with(shared_asset.id, active_workflow.id)
      expect(response.parsed_body['queued']).to eq(1)
    end

    it 'allows non-admin authenticated users to trigger' do
      sign_out admin
      sign_in user
      allow(WorkflowInitiatorWorker).to receive(:perform_async)

      post '/api/v1/workflows/bulk_trigger', params: { workflow_id: active_workflow.id, asset_ids: [ asset.id ] }

      expect(response).to have_http_status(:accepted)
    end
  end

  describe 'authorization' do
    it 'forbids non-admin users' do
      sign_out admin
      sign_in user

      get '/api/v1/workflow_instances'

      expect(response).to have_http_status(:forbidden)
    end
  end
end
