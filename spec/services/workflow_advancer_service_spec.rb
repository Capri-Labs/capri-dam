require 'rails_helper'

RSpec.describe WorkflowAdvancerService do
  let(:approver) { create(:user) }
  let(:asset)    { create(:asset, status: 'in_review') }
  let(:workflow) { create(:workflow) }
  let(:instance) { create(:workflow_instance, asset: asset, workflow: workflow, status: 'in_progress') }

  def approval_step(position)
    create(:workflow_step, workflow: workflow, position: position, step_type: 'approval',
                           node_type: 'approval', assignee_type: 'user', assignee_id: approver.id, logic: 'any')
  end

  def automated_step(position, node_type, config = {})
    create(:workflow_step, workflow: workflow, position: position, step_type: 'automated_action',
                           node_type: node_type, assignee_type: 'system', assignee_id: 0, step_config: config)
  end

  describe '#process_step' do
    it 'generates a task for an approval step and waits' do
      step = approval_step(1)
      expect { described_class.new(instance).process_step(step) }
        .to change { instance.workflow_tasks.count }.by(1)
      expect(instance.reload.current_step_id).to eq(step.id)
      expect(instance.status).to eq('in_progress')
    end

    it 'executes an automated step then advances to the next approval step' do
      auto = automated_step(1, 'set_status', { 'status' => 'approved' })
      gate = approval_step(2)

      described_class.new(instance).process_step(auto)

      expect(asset.reload.read_attribute_before_type_cast('status')).to eq(Asset.statuses['approved'].to_s) # action ran
      expect(instance.reload.current_step_id).to eq(gate.id) # advanced to approval
      expect(instance.workflow_tasks.count).to eq(1)         # task created for the gate
    end

    it 'completes the instance when the chain ends on an automated step' do
      auto = automated_step(1, 'archive')

      described_class.new(instance).process_step(auto)

      expect(asset.reload.deleted_at).to be_present
      expect(instance.reload.status).to eq('completed')
      expect(instance.completed_at).to be_present
    end

    it 'falls back to the workflow escalation assignee when the step has none' do
      fallback = create(:user)
      workflow.update!(fallback_assignee_type: 'user', fallback_assignee_id: fallback.id)
      step = create(:workflow_step, workflow: workflow, position: 1, step_type: 'approval',
                                    node_type: 'approval', assignee_type: 'user', assignee_id: 0, logic: 'any')

      described_class.new(instance).process_step(step)

      expect(instance.workflow_tasks.last.user).to eq(fallback)
    end
  end
end
