require 'rails_helper'

RSpec.describe WorkflowAdvancerService do
  let(:approver) { create(:user) }
  let(:asset)    { create(:asset, status: 'in_review') }
  let(:workflow) { create(:workflow) }
  let(:instance) { create(:workflow_instance, asset: asset, workflow: workflow, status: 'in_progress') }

  def approval_step(position, overrides = {})
    create(:workflow_step, workflow: workflow, position: position, step_type: 'approval',
                           node_type: 'approval', assignee_type: 'user', assignee_id: approver.id,
                           logic: 'any', **overrides)
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

      expect(asset.reload.read_attribute_before_type_cast('status')).to eq(Asset.statuses['approved'].to_s)
      expect(instance.reload.current_step_id).to eq(gate.id)
      expect(instance.workflow_tasks.count).to eq(1)
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

    # ── Step-level vs workflow-level fallback priority ────────────────────────

    context 'when the primary assignee cannot be resolved' do
      it 'uses the step-level fallback assignee when configured' do
        step_fallback = create(:user)
        step = approval_step(1, assignee_id: 0,
                             fallback_assignee_type: 'user',
                             fallback_assignee_id:   step_fallback.id.to_s)

        described_class.new(instance).process_step(step)

        expect(instance.workflow_tasks.last.user).to eq(step_fallback)
      end

      it 'prefers the step-level fallback over the workflow-level fallback' do
        step_fb = create(:user)
        wf_fb   = create(:user)
        workflow.update!(fallback_assignee_type: 'user', fallback_assignee_id: wf_fb.id)
        step = approval_step(1, assignee_id: 0,
                             fallback_assignee_type: 'user',
                             fallback_assignee_id:   step_fb.id.to_s)

        described_class.new(instance).process_step(step)

        expect(instance.workflow_tasks.last.user).to eq(step_fb)
      end

      it 'resolves a step-level group fallback to all of its members' do
        member_a = create(:user)
        member_b = create(:user)
        group    = create(:user_group)
        group.users << member_a
        group.users << member_b

        step = approval_step(1, assignee_id: 0,
                             fallback_assignee_type: 'group',
                             fallback_assignee_id:   group.id.to_s)

        described_class.new(instance).process_step(step)

        assigned = instance.workflow_tasks.map(&:user)
        expect(assigned).to include(member_a, member_b)
      end

      it 'logs FATAL and creates no task when no fallback exists at any level' do
        workflow.update!(fallback_assignee_type: nil, fallback_assignee_id: nil)
        step = approval_step(1, assignee_id: 0,
                             fallback_assignee_type: 'user',
                             fallback_assignee_id:   '')

        expect(Rails.logger).to receive(:error).with(/FATAL/)
        described_class.new(instance).process_step(step)

        expect(instance.workflow_tasks.count).to eq(0)
      end
    end

    it 'stops advancing when a delay step is encountered (WorkflowDelayWorker scheduled)' do
      allow(WorkflowDelayWorker).to receive(:perform_in)
      delay = automated_step(1, 'delay', { 'delayValue' => 1, 'delayUnit' => 'hours' })
      gate  = approval_step(2)

      described_class.new(instance).process_step(delay)

      # Should have stopped — gate task not yet created
      expect(instance.workflow_tasks.count).to eq(0)
      expect(WorkflowDelayWorker).to have_received(:perform_in)
    end

    it 'raises when the automated chain exceeds MAX_AUTOMATED_CHAIN' do
      # Build a long chain of set_status steps with the same position
      # by stubbing next_step_after to always return the same step.
      step = automated_step(1, 'set_status', { 'status' => 'approved' })
      allow_any_instance_of(described_class).to receive(:next_step_after).and_return(step)

      expect {
        described_class.new(instance).process_step(step)
      }.to raise_error(/cycle/)
    end
  end
end
