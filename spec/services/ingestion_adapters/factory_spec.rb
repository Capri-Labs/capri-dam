require 'rails_helper'

RSpec.describe IngestionAdapters::Factory, type: :service do
  describe '.build' do
    it 'builds an adapter using inline source credentials' do
      batch = build_stubbed(:ingestion_batch, source_type: 'aem', source_credentials: { endpoint: 'https://aem.example.com', auth_token: 'token' })

      expect(IngestionAdapters::AemAdapter).to receive(:new).with(batch, hash_including(
        'endpoint' => 'https://aem.example.com',
        'auth_token' => 'token'
      )).and_return(:adapter)

      expect(described_class.build(batch)).to eq(:adapter)
    end

    it 'falls back to connector credentials when inline credentials are blank' do
      connector = build_stubbed(:system_connector, endpoint: 'https://dam.example.com', auth_token: 'connector-token')
      batch = build_stubbed(:ingestion_batch, source_type: 'aem', source_credentials: {}, connector: connector)

      expect(IngestionAdapters::AemAdapter).to receive(:new).with(batch, hash_including(
        'endpoint' => 'https://dam.example.com',
        'auth_token' => 'connector-token'
      )).and_return(:adapter)

      described_class.build(batch)
    end

    it 'raises for unknown providers' do
      batch = build_stubbed(:ingestion_batch, source_type: 'unknown', source_credentials: {})

      expect { described_class.build(batch) }.to raise_error(ArgumentError, /Unknown migration source/)
    end
  end

  describe '.test' do
    it 'delegates to the adapter test connection' do
      adapter = instance_double(IngestionAdapters::AemAdapter, test_connection: { success: true })
      expect(IngestionAdapters::AemAdapter).to receive(:new).with(nil, { endpoint: 'https://aem.example.com' }).and_return(adapter)

      expect(described_class.test('aem', { endpoint: 'https://aem.example.com' })).to eq(success: true)
    end

    it 'returns a failure payload when the adapter raises' do
      allow(IngestionAdapters::AemAdapter).to receive(:new).and_raise(StandardError, 'boom')

      expect(described_class.test('aem', {})).to eq(success: false, message: 'boom')
    end

    it 'raises for unknown providers' do
      expect { described_class.test('unknown', {}) }.not_to raise_error
      expect(described_class.test('unknown', {})).to eq(success: false, message: 'Unknown provider: unknown')
    end
  end
end
