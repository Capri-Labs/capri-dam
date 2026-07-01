require 'rails_helper'

RSpec.describe MentionProcessorWorker, type: :worker do
  describe '#perform' do
    let(:sender) { create(:user) }

    it 'calls InboxDeliveryService.deliver_mention' do
      allow(InboxDeliveryService).to receive(:deliver_mention)

      described_class.new.perform('Hello @test', sender.id, '/assets/1')

      expect(InboxDeliveryService).to have_received(:deliver_mention).with(
        text: 'Hello @test',
        sender: sender,
        context_url: '/assets/1',
        reference: nil
      )
    end

    it 'handles a missing sender gracefully' do
      expect { described_class.new.perform('Hello', 0) }.not_to raise_error
    end
  end
end
