require 'rails_helper'

RSpec.describe WorkflowDelayWorker, type: :worker do
  let(:user)     { create(:user) }
  let(:asset)    { create(:asset, user: user, status: 'in_review') }
  let(:workflow) { create(:workflow) }
  let(:instance) { create(:workflow_instance, asset: asset, workflow: workflow, status: 'in_progress') }

  def delay_step(position = 1)
    create(:workflow_step,
           workflow:      workflow,
           position:      position,
           step_type:     'automated_action',
           node_type:     'delay',
           assignee_type: 'system',
           assignee_id:   0,
           step_config:   { 'delayValue' => 1, 'delayUnit' => 'hours' })
  end

  describe '#perform' do
    it 'does nothing when the instance is not found' do
      expect(WorkflowAdvancerService).not_to receive(:new)
      described_class.new.perform(0, 0)
    end

    it 'does nothing when the instance is terminal (cancelled)' do
      instance.update!(status: 'canceled')
      step = delay_step
      expect(WorkflowAdvancerService).not_to receive(:new)
      described_class.new.perform(instance.id, step.id)
    end

    it 'advances to the next step when the instance is in_progress' do
      dstep = delay_step(1)
      gate  = create(:workflow_step, workflow: workflow, position: 2,
                     step_type: 'approval', node_type: 'approval',
                     assignee_type: 'user', assignee_id: user.id, logic: 'any')

      allow(WorkflowAdvancerService).to receive(:new).and_call_original
      described_class.new.perform(instance.id, dstep.id)

      expect(instance.reload.current_step_id).to eq(gate.id)
    end

    it 'completes the instance when the delay is the last step' do
      dstep = delay_step(1)
      described_class.new.perform(instance.id, dstep.id)

      expect(instance.reload.status).to eq('completed')
      expect(asset.reload.read_attribute_before_type_cast('status')).to eq(Asset.statuses['approved'].to_s)
    end
  end
end
