require 'rails_helper'

RSpec.describe Workflow, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:workflow)).to be_valid
    end

    it 'requires a name' do
      expect(build(:workflow, name: nil)).not_to be_valid
    end

    it 'requires a trigger_type' do
      expect(build(:workflow, trigger_type: nil)).not_to be_valid
    end
  end

  describe 'active workflow must have steps' do
    it 'is valid when draft has no steps' do
      wf = build(:workflow, status: :draft)
      expect(wf).to be_valid
    end

    it 'is invalid when active and has no steps' do
      wf = build(:workflow, status: :active)
      expect(wf).not_to be_valid
      expect(wf.errors[:base]).to include('Active workflows must have at least one approval step')
    end

    it 'is valid when active and has at least one step' do
      wf   = create(:workflow, status: :draft)
      step = create(:workflow_step, workflow: wf)
      wf.reload
      wf.status = :active
      expect(wf).to be_valid
    end
  end

  describe 'status enum' do
    it 'transitions between states' do
      wf = create(:workflow)
      wf.update!(status: :inactive)
      expect(wf.reload.status).to eq('inactive')
    end
  end
end
