require 'rails_helper'

RSpec.describe SystemConnector, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:system_connector)).to be_valid
    end

    it 'requires a name' do
      expect(build(:system_connector, name: nil)).not_to be_valid
    end

    it 'requires a valid provider_type' do
      expect(build(:system_connector, provider_type: 'bogus')).not_to be_valid
    end

    it 'requires an http(s) endpoint for non-FTP providers' do
      expect(build(:system_connector, endpoint: 'not-a-url')).not_to be_valid
    end

    it 'allows a bare hostname for FTP providers' do
      expect(build(:system_connector, :ftp)).to be_valid
    end
  end

  describe 'before_create callback' do
    it 'auto-generates a webhook_secret' do
      connector = create(:system_connector)
      expect(connector.webhook_secret).to be_present
      expect(connector.webhook_secret.length).to eq(64)
    end
  end

  describe '#provider_label' do
    it 'returns a human-readable label' do
      connector = build(:system_connector, provider_type: 'aem')
      expect(connector.provider_label).to eq('Adobe Experience Manager')
    end
  end

  describe '#test_connection' do
    it 'delegates to IngestionAdapters::Factory.test with the connector credentials' do
      connector = build(:system_connector, provider_type: 'aem')
      expect(IngestionAdapters::Factory).to receive(:test)
        .with('aem', { 'endpoint' => connector.endpoint, 'auth_token' => connector.auth_token })
        .and_return({ success: true })

      expect(connector.test_connection).to eq({ success: true })
    end

    it 'rescues adapter errors and returns a failure hash' do
      connector = build(:system_connector, provider_type: 'aem')
      allow(IngestionAdapters::Factory).to receive(:test).and_raise(StandardError.new('boom'))

      expect(connector.test_connection).to eq({ success: false, message: 'boom' })
    end
  end
end
