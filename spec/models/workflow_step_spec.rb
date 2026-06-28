require 'rails_helper'

RSpec.describe WorkflowStep, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:workflow_step)).to be_valid
    end

    %i[step_type assignee_type assignee_id logic position].each do |attr|
      it "requires #{attr}" do
        expect(build(:workflow_step, attr => nil)).not_to be_valid
      end
    end

    it 'rejects unknown node_type values' do
      step = build(:workflow_step, node_type: 'totally_unknown')
      expect(step).not_to be_valid
      expect(step.errors[:node_type]).to be_present
    end

    it 'accepts nil node_type (legacy approval rows)' do
      step = build(:workflow_step, node_type: nil)
      expect(step).to be_valid
    end

    WorkflowStep::NODE_TYPES.each do |nt|
      it "accepts node_type '#{nt}'" do
        attrs = { node_type: nt }
        if WorkflowStep::URL_NODE_TYPES.include?(nt)
          attrs.merge!(step_type: 'automated_action', assignee_type: 'system',
                       assignee_id: 0, step_config: { 'url' => 'https://example.com' })
        elsif nt == 'email_notification'
          attrs.merge!(step_type: 'automated_action', assignee_type: 'system',
                       assignee_id: 0, step_config: { 'subject' => 'Hello' })
        elsif nt != 'approval'
          attrs.merge!(step_type: 'automated_action', assignee_type: 'system', assignee_id: 0)
        end
        step = build(:workflow_step, **attrs)
        expect(step).to be_valid, "Expected valid for node_type #{nt}: #{step.errors.full_messages}"
      end
    end
  end

  describe 'config validations' do
    it 'is invalid when a webhook node has no URL' do
      step = build(:workflow_step, step_type: 'automated_action', node_type: 'webhook',
                   assignee_type: 'system', assignee_id: 0, logic: 'any', step_config: {})
      expect(step).not_to be_valid
      expect(step.errors[:step_config].join).to include('URL')
    end

    it 'is invalid when email_notification has no subject' do
      step = build(:workflow_step, step_type: 'automated_action', node_type: 'email_notification',
                   assignee_type: 'system', assignee_id: 0, logic: 'any',
                   step_config: { 'recipient' => 'assignee' })
      expect(step).not_to be_valid
      expect(step.errors[:step_config].join).to include('subject')
    end
  end

  describe 'associations' do
    it 'belongs to a workflow' do
      step = create(:workflow_step)
      expect(step.workflow).to be_present
    end
  end

  describe '#resolve_assignee' do
    it 'returns a User when assignee_type is user' do
      user = create(:user)
      step = create(:workflow_step, assignee_type: 'user', assignee_id: user.id)
      expect(step.resolve_assignee).to eq(user)
    end

    it 'returns nil for an unknown ID' do
      step = create(:workflow_step, assignee_type: 'user', assignee_id: 0)
      expect(step.resolve_assignee).to be_nil
    end
  end
end
