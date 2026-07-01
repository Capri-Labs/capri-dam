require 'rails_helper'

RSpec.describe InboxCleanupWorker, type: :worker do
  describe '#perform' do
    it 'archives old read messages' do
      message = create(:inbox_message, :read, archived_at: nil, read_at: 91.days.ago)

      described_class.new.perform

      expect(message.reload.archived_at).to be_present
    end

    it 'deletes old archived messages' do
      message = create(:inbox_message, archived_at: 1.year.ago - 1.day)

      described_class.new.perform

      expect { message.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
