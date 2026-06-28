require 'rails_helper'

RSpec.describe WorkflowSmsWorker, type: :worker do
  let(:user)     { create(:user) }
  let(:asset)    { create(:asset, user: user, title: 'Test Asset') }
  let(:workflow) { create(:workflow) }
  let(:instance) { create(:workflow_instance, asset: asset, workflow: workflow, status: 'in_progress') }

  before do
    ENV.delete('TWILIO_ACCOUNT_SID')
    ENV.delete('TWILIO_AUTH_TOKEN')
    ENV.delete('TWILIO_FROM_NUMBER')
  end

  it 'does nothing when phone is blank' do
    expect(Rails.logger).not_to receive(:info).with(/SMS/)
    described_class.new.perform(instance.id, '', 'Hello')
  end

  it 'does nothing when message is blank' do
    expect(Rails.logger).not_to receive(:info).with(/SMS/)
    described_class.new.perform(instance.id, '+15550001234', '')
  end

  it 'logs the SMS in development (no Twilio credentials)' do
    expect(Rails.logger).to receive(:info)
      .with(a_string_including('SMS to +15550001234'))
    described_class.new.perform(instance.id, '+15550001234', 'Hello Test Asset')
  end

  it 'expands {{asset.title}} tokens' do
    expect(Rails.logger).to receive(:info) do |msg|
      expect(msg).to include(asset.title)
    end
    described_class.new.perform(instance.id, '+15550001234', 'Check {{asset.title}}')
  end

  it 'raises and retries on Faraday errors' do
    ENV['TWILIO_ACCOUNT_SID'] = 'ACtest'
    ENV['TWILIO_AUTH_TOKEN']  = 'token'
    ENV['TWILIO_FROM_NUMBER'] = '+10000000000'

    conn = instance_double(Faraday::Connection)
    allow(Faraday).to receive(:new).and_return(conn)
    allow(conn).to receive(:post).and_raise(Faraday::ConnectionFailed.new('timeout'))

    expect {
      described_class.new.perform(instance.id, '+15550001234', 'Hello')
    }.to raise_error(Faraday::ConnectionFailed)
  ensure
    ENV.delete('TWILIO_ACCOUNT_SID')
    ENV.delete('TWILIO_AUTH_TOKEN')
    ENV.delete('TWILIO_FROM_NUMBER')
  end
end
