require 'rails_helper'

RSpec.describe InboxMessage, type: :model do
  let(:user) { create(:user) }
  let(:sender) { create(:user) }

  subject(:message) { build(:inbox_message, recipient: user, sender: sender) }

  describe 'validations' do
    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:subject) }
    it { is_expected.to validate_inclusion_of(:message_type).in_array(InboxMessage::MESSAGE_TYPES) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:recipient).class_name('User') }
    it { is_expected.to belong_to(:sender).class_name('User').optional }
    it { is_expected.to belong_to(:email_template).optional }
  end

  describe 'scopes' do
    it 'unread returns messages without read_at' do
      unread_message = create(:inbox_message, recipient: user, read_at: nil)
      read_message = create(:inbox_message, recipient: user, read_at: 1.hour.ago)

      expect(InboxMessage.unread).to include(unread_message)
      expect(InboxMessage.unread).not_to include(read_message)
    end

    it 'active returns non-archived messages' do
      active_message = create(:inbox_message, recipient: user, archived_at: nil)
      archived_message = create(:inbox_message, recipient: user, archived_at: 1.hour.ago)

      expect(InboxMessage.active).to include(active_message)
      expect(InboxMessage.active).not_to include(archived_message)
    end
  end

  describe '#mark_read!' do
    it 'sets read_at timestamp' do
      unread_message = create(:inbox_message, recipient: user, read_at: nil)

      expect { unread_message.mark_read! }.to change { unread_message.reload.read_at }.from(nil)
    end

    it 'is idempotent' do
      time = 1.hour.ago
      read_message = create(:inbox_message, recipient: user, read_at: time)

      read_message.mark_read!

      expect(read_message.reload.read_at).to be_within(1.second).of(time)
    end
  end

  describe '#star!' do
    it 'sets starred_at when not starred' do
      unstarred_message = create(:inbox_message, recipient: user, starred_at: nil)

      expect { unstarred_message.star! }.to change { unstarred_message.reload.starred_at }.from(nil)
    end

    it 'clears starred_at when already starred' do
      starred_message = create(:inbox_message, recipient: user, starred_at: 1.hour.ago)

      expect { starred_message.star! }.to change { starred_message.reload.starred_at }.to(nil)
    end
  end
end
