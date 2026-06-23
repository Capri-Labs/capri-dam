require 'rails_helper'

RSpec.describe Notification, type: :model do
  describe '.unread scope' do
    it 'returns only notifications without a read_at timestamp' do
      user   = create(:user)
      unread = create(:notification, user: user, read_at: nil)
      read   = create(:notification, user: user, read_at: Time.current)

      expect(Notification.unread).to include(unread)
      expect(Notification.unread).not_to include(read)
    end
  end

  describe 'associations' do
    it 'belongs to a user' do
      expect(create(:notification).user).to be_present
    end
  end
end
