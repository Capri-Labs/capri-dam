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
  end

  describe 'associations' do
    it 'belongs to a workflow' do
      step = create(:workflow_step)
      expect(step.workflow).to be_present
    end
  end
end
