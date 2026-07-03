# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API workflow task coverage', type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:asset) { create(:asset, user: user, title: 'Board Image') }
  let(:workflow) { create(:workflow, name: 'Approval Flow') }
  let(:step) do
    create(:workflow_step, workflow: workflow, title: 'Board Approval', assignee_type: 'user', assignee_id: user.id)
  end
  let(:instance) do
    create(:workflow_instance,
           asset: asset,
           workflow: workflow,
           current_step: step,
           status: 'in_progress',
           started_at: 1.hour.ago)
  end
  let(:task) { create(:workflow_task, workflow_instance: instance, workflow_step: step, user: user) }

  before { sign_in user }

  describe 'POST /api/v1/workflow_tasks/:id/submit' do
    it 'records an assigned user decision and enqueues the engine' do
      allow(WorkflowEngineWorker).to receive(:perform_async)

      post "/api/v1/workflow_tasks/#{task.id}/submit", params: { decision: 'approved', comment: 'Ship it' }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('success' => true, 'message' => 'Decision recorded')
      expect(task.reload).to have_attributes(status: 'approved', comment: 'Ship it')
      expect(task.completed_at).to be_present
      expect(WorkflowEngineWorker).to have_received(:perform_async).with(task.id)
    end

    it 'rejects submissions from users who are not assigned' do
      sign_out user
      sign_in other_user

      post "/api/v1/workflow_tasks/#{task.id}/submit", params: { decision: 'approved' }

      expect(response).to have_http_status(:forbidden)
      expect(task.reload.status).to eq('pending')
    end

    it 'rejects tasks that are no longer pending' do
      task.update!(status: 'approved', completed_at: Time.current)

      post "/api/v1/workflow_tasks/#{task.id}/submit", params: { decision: 'rejected' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Task is no longer pending')
    end
  end

  describe 'GET /api/v1/workflows/dashboard' do
    it 'returns assigned tasks, active workflows, and completed workflows' do
      task
      untitled_asset = create(:asset)
      untitled_asset.update_column(:title, '')
      completed = create(:workflow_instance,
                         asset: untitled_asset,
                         workflow: workflow,
                         status: 'completed',
                         completed_at: Time.current)

      get '/api/v1/workflows/dashboard'

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['my_tasks']).to contain_exactly(hash_including(
        'task_id' => task.id,
        'step_title' => 'Board Approval',
        'asset_id' => asset.id,
        'asset_name' => 'Board Image'
      ))
      expect(body['active_workflows']).to include(hash_including(
        'instance_id' => instance.id,
        'workflow_name' => 'Approval Flow',
        'current_step' => 'Board Approval',
        'asset_id' => asset.id
      ))
      expect(body['completed_workflows']).to include(hash_including(
        'instance_id' => completed.id,
        'workflow_name' => 'Approval Flow',
        'asset_name' => 'Untitled Asset',
        'status' => 'completed'
      ))
    end
  end

  describe 'POST /api/v1/workflows/bulk_stop' do
    it 'cancels instances, only cancels pending tasks, and soft-deletes the asset' do
      task
      completed_task = create(
        :workflow_task,
        workflow_instance: instance,
        workflow_step: step,
        user: user,
        status: 'approved',
        comment: 'Already done',
        completed_at: 2.minutes.ago
      )

      with_routing do |set|
        set.draw do
          post '/spec/workflow_tasks/bulk_stop', to: 'api/v1/workflow_tasks#bulk_stop'
        end

        post '/spec/workflow_tasks/bulk_stop', params: { ids: [ instance.id ] }, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq('success' => true)
      end

      expect(instance.reload).to have_attributes(status: 'canceled')
      expect(instance.completed_at).to be_present
      expect(task.reload).to have_attributes(
        status: 'canceled',
        comment: "Admin Action: Workflow manually stopped by #{user.email}"
      )
      expect(task.completed_at).to be_present
      expect(completed_task.reload).to have_attributes(status: 'approved', comment: 'Already done')
      expect(asset.reload.deleted_at).to be_present
    end
  end
end
