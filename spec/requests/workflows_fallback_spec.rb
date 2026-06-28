require 'rails_helper'

# Focused controller-behaviour specs for the Visual Workflow Designer v2 refactor.
#
# These complement the rswag documentation specs in workflows_spec.rb and
# specifically guard the escalation refactor:
#   • step-level fallback_assignee_* params are PERSISTED
#   • workflow-level fallback_assignee_* params are NO LONGER mass-assignable
RSpec.describe 'Workflows step-level fallback persistence', type: :request do
  let(:user)  { create(:user, :admin) }
  let(:group) { create(:user_group) }

  before { sign_in user }

  describe 'POST /workflows' do
    let(:base_payload) do
      {
        workflow: {
          name:         'Brand Compliance',
          trigger_type: 'manual',
          status:       'active',
          workflow_steps_attributes: [
            {
              title:                  'Legal Review',
              position:               1,
              step_type:              'approval',
              node_type:              'approval',
              assignee_type:          'user',
              assignee_id:            user.id.to_s,
              fallback_assignee_type: 'group',
              fallback_assignee_id:   group.id.to_s,
              logic:                  'any',
              deadline_days:          3,
            },
          ],
        },
      }
    end

    it 'persists step-level fallback assignee fields' do
      post '/workflows', params: base_payload, as: :json

      expect(response).to have_http_status(:created)
      step = Workflow.last.workflow_steps.first
      expect(step.fallback_assignee_type).to eq('group')
      expect(step.fallback_assignee_id).to eq(group.id.to_s)
    end

    it 'ignores a workflow-level fallback_assignee (no longer permitted)' do
      payload = base_payload.deep_dup
      payload[:workflow][:fallback_assignee_type] = 'user'
      payload[:workflow][:fallback_assignee_id]   = '12345'

      post '/workflows', params: payload, as: :json

      expect(response).to have_http_status(:created)
      wf = Workflow.last
      # The workflow-level fallback columns remain at their default/blank values
      # because the param is filtered out by strong parameters.
      expect(wf.fallback_assignee_id.to_s).not_to eq('12345')
    end
  end

  describe 'PUT /workflows/:id' do
    let!(:step) do
      build(:workflow_step, position: 1, step_type: 'approval',
                            node_type: 'approval', assignee_type: 'user', assignee_id: user.id,
                            logic: 'any', fallback_assignee_type: 'user', fallback_assignee_id: '')
    end
    let!(:workflow) { create(:workflow, status: :active, workflow_steps: [ step ]) }

    it 'updates the step-level fallback assignee' do
      put "/workflows/#{workflow.id}", params: {
        workflow: {
          name: workflow.name,
          workflow_steps_attributes: [
            {
              id:                     step.id,
              fallback_assignee_type: 'group',
              fallback_assignee_id:   group.id.to_s,
            },
          ],
        },
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(step.reload.fallback_assignee_type).to eq('group')
      expect(step.fallback_assignee_id).to eq(group.id.to_s)
    end
  end
end
