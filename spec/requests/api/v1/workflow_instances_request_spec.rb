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

  describe 'authorization' do
    it 'forbids non-admin users' do
      sign_out admin
      sign_in user

      get '/api/v1/workflow_instances'

      expect(response).to have_http_status(:forbidden)
    end
  end
end
