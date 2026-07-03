require 'rails_helper'

RSpec.describe InboxDeliveryService do
  let(:recipient) { create(:user) }
  let(:sender) { create(:user, first_name: 'Alice', last_name: 'Sender') }
  let!(:template) { create(:email_template, event_trigger: 'user_mentioned', active: true) }

  describe '.deliver' do
    it 'creates an inbox message' do
      expect do
        described_class.deliver(recipient: recipient, subject: 'Hello', body_html: '<p>Hello</p>')
      end.to change(InboxMessage, :count).by(1)
    end

    it 'stores reference metadata and skips email delivery when mention emails are disabled' do
      recipient.preference.update!(receive_mention_emails: false)
      asset = create(:asset, user: sender)

      expect(EmailDispatcherWorker).not_to receive(:perform_async)

      message = described_class.deliver(
        recipient: recipient,
        sender: sender,
        subject: 'Asset updated',
        body_html: '<p>Updated</p>',
        reference: asset
      )

      expect(message.reference_type).to eq('Asset')
      expect(message.reference_id).to eq(asset.id)
    end
  end

  describe '.deliver_mention' do
    let!(:mentioned_one) { create(:user, username: 'bob') }
    let!(:mentioned_two) { create(:user, username: 'carol') }

    it 'creates messages for all mentioned users' do
      expect do
        described_class.deliver_mention(text: 'Hey @bob and @carol', sender: sender)
      end.to change(InboxMessage, :count).by(2)
    end

    it 'does not create a message for self-mention' do
      sender.update!(username: 'alice_sender')

      expect do
        described_class.deliver_mention(text: 'Hey @alice_sender', sender: sender)
      end.not_to change(InboxMessage, :count)
    end

    it 'triggers EmailDispatcherWorker when mention emails are enabled' do
      mentioned_one.preference.update!(receive_mention_emails: true)
      allow(EmailDispatcherWorker).to receive(:perform_async)

      described_class.deliver_mention(text: 'Hello @bob', sender: sender)

      expect(EmailDispatcherWorker).to have_received(:perform_async).once
    end

    it 'defaults to email delivery when the recipient preference is missing and includes the context link' do
      mentioned_one.preference.destroy!
      allow(EmailDispatcherWorker).to receive(:perform_async)

      described_class.deliver_mention(text: 'Hello @bob', sender: sender, context_url: '/assets/123')

      message = InboxMessage.order(:created_at).last
      expect(message.body_html).to include('View in context', '/assets/123')
      expect(EmailDispatcherWorker).to have_received(:perform_async).once
    end
  end
end
