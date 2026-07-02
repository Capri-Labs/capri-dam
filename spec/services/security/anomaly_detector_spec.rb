require 'rails_helper'

RSpec.describe Security::AnomalyDetector, type: :service do
  let(:user) { create(:user) }

  it 'does nothing below the rapid admin modification threshold' do
    create_list(:audit_log, 10, user: user, action: 'update', auditable_type: 'User')

    expect(described_class.analyze(user.id)).to be_nil
  end

  it 'triggers a security alert above the threshold' do
    create_list(:audit_log, 11, user: user, action: 'update', auditable_type: 'User')
    described_class.singleton_class.define_method(:trigger_security_alert) { |*_args| true }
    allow(described_class).to receive(:trigger_security_alert)

    described_class.analyze(user.id)

    expect(described_class).to have_received(:trigger_security_alert).with(user.id, 'Rapid Admin modifications detected.')
  end
end
