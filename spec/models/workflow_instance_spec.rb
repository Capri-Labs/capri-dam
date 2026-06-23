require 'rails_helper'

RSpec.describe WorkflowInstance, type: :model do
  describe 'associations' do
    it 'belongs to an asset and a workflow' do
      wi = create(:workflow_instance)
      expect(wi.asset).to be_present
      expect(wi.workflow).to be_present
    end
  end

  describe '#transition_to!' do
    it 'appends an audit entry and updates status' do
      user = create(:user)
      wi   = create(:workflow_instance)
      wi.transition_to!('approved', user, 'Looks great')

      wi.reload
      expect(wi.status).to eq('approved')
      expect(wi.audit_log.last['action']).to eq('approved')
      expect(wi.audit_log.last['note']).to eq('Looks great')
      expect(wi.last_action_by).to eq(user)
    end
  end
end
