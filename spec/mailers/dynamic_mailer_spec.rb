require 'rails_helper'

RSpec.describe DynamicMailer, type: :mailer do
  describe '#dispatch_email' do
    it 'renders html and text alternatives using the configured recipient and subject' do
      mail = described_class.dispatch_email(
        to: 'recipient@example.com',
        subject: 'Asset update',
        html_body: '<strong>Hello</strong>',
        text_body: 'Hello'
      )

      expect(mail.to).to eq([ 'recipient@example.com' ])
      expect(mail.subject).to eq('Asset update')
      expect(mail.from).to eq([ ENV.fetch('MAILER_SENDER_ADDRESS', 'noreply@yourdam.com') ])
      expect(mail.html_part.body.decoded).to include('<strong>Hello</strong>')
      expect(mail.text_part.body.decoded).to include('Hello')
    end
  end
end
