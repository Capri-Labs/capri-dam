require 'rails_helper'

RSpec.describe ScheduledPublishAction, type: :model do
  let(:user) { create(:user) }
  let(:asset) { create(:asset) }

  describe 'validations' do
    it 'is valid with a supported action_type and scheduled_at' do
      action = build(:scheduled_publish_action, asset: asset, created_by: user)
      expect(action).to be_valid
    end

    it 'rejects an unsupported action_type' do
      action = build(:scheduled_publish_action, asset: asset, created_by: user, action_type: 'archive')
      expect(action).not_to be_valid
    end

    it 'requires scheduled_at' do
      action = build(:scheduled_publish_action, asset: asset, created_by: user, scheduled_at: nil)
      expect(action).not_to be_valid
    end
  end

  describe 'defaults' do
    it 'defaults status to pending' do
      expect(create(:scheduled_publish_action, asset: asset, created_by: user)).to be_pending
    end
  end

  describe '.due' do
    it 'includes only pending rows whose scheduled_at has passed' do
      due = create(:scheduled_publish_action, asset: asset, created_by: user, scheduled_at: 1.minute.ago)
      future = create(:scheduled_publish_action, asset: create(:asset), created_by: user,
                                                  action_type: 'unpublish', scheduled_at: 1.hour.from_now)
      completed = create(:scheduled_publish_action, asset: create(:asset), created_by: user,
                                                     scheduled_at: 1.minute.ago, status: :completed)

      expect(ScheduledPublishAction.due).to include(due)
      expect(ScheduledPublishAction.due).not_to include(future, completed)
    end
  end

  describe '#apply!' do
    it 'publishes the asset and marks the row completed for a "publish" action' do
      action = create(:scheduled_publish_action, asset: asset, created_by: user, action_type: 'publish')

      action.apply!

      expect(asset.reload).to be_published
      expect(action.reload).to be_completed
      expect(action.executed_at).to be_present
    end

    it 'unpublishes the asset for an "unpublish" action' do
      asset.publish!
      action = create(:scheduled_publish_action, asset: asset, created_by: user, action_type: 'unpublish')

      action.apply!

      expect(asset.reload).not_to be_published
      expect(action.reload).to be_completed
    end

    it 'marks the row failed and re-raises when the update fails' do
      action = create(:scheduled_publish_action, asset: asset, created_by: user, action_type: 'publish')
      allow(asset).to receive(:publish!).and_raise(StandardError.new('boom'))
      allow(action).to receive(:asset).and_return(asset)

      expect { action.apply! }.to raise_error(StandardError, 'boom')
      expect(action.reload).to be_failed
      expect(action.error_message).to eq('boom')
    end
  end
end
