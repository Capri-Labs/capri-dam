require 'rails_helper'

RSpec.describe EmailDelivery, type: :model do
  subject(:email_delivery) { build(:email_delivery) }

  describe 'associations' do
    it { is_expected.to belong_to(:email_template) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:recipient_email) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending sent failed]) }
    it { is_expected.to validate_numericality_of(:retry_count).is_greater_than_or_equal_to(0) }
  end

  describe 'scopes' do
    let!(:pending_delivery) { create(:email_delivery, status: 'pending') }
    let!(:sent_delivery) { create(:email_delivery, status: 'sent') }
    let!(:failed_delivery) { create(:email_delivery, status: 'failed') }

    it '.pending returns pending deliveries' do
      expect(described_class.pending).to contain_exactly(pending_delivery)
    end

    it '.sent returns sent deliveries' do
      expect(described_class.sent).to contain_exactly(sent_delivery)
    end

    it '.failed returns failed deliveries' do
      expect(described_class.failed).to contain_exactly(failed_delivery)
    end
  end

  describe '#max_retries_reached?' do
    it 'is true when the retry count is 3 or greater' do
      expect(build(:email_delivery, retry_count: 3)).to be_max_retries_reached
    end

    it 'is false when the retry count is below 3' do
      expect(build(:email_delivery, retry_count: 2)).not_to be_max_retries_reached
    end
  end

  describe '#mark_as_sent!' do
    it 'marks the delivery as sent and clears the error log' do
      delivery = create(:email_delivery, status: 'failed', error_log: 'SMTP failure')

      delivery.mark_as_sent!

      expect(delivery.reload.status).to eq('sent')
      expect(delivery.error_log).to be_nil
    end
  end

  describe '#mark_as_failed!' do
    it 'marks the delivery as failed and stores the error message' do
      delivery = create(:email_delivery)

      delivery.mark_as_failed!('Mailbox unavailable')

      expect(delivery.reload.status).to eq('failed')
      expect(delivery.error_log).to eq('Mailbox unavailable')
    end
  end
end
