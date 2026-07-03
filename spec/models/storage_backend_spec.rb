require 'rails_helper'

RSpec.describe StorageBackend, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:storage_backend)).to be_valid
    end

    it 'requires a name' do
      expect(build(:storage_backend, name: nil)).not_to be_valid
    end

    it 'requires a valid provider_type' do
      expect(build(:storage_backend, provider_type: 'unknown_provider')).not_to be_valid
    end

    it 'accepts all documented provider types' do
      StorageBackend::PROVIDER_TYPES.each do |type|
        expect(build(:storage_backend, provider_type: type)).to be_valid
      end
    end
  end

  describe '#masked_configuration' do
    it 'masks keys matching secret/key/password/token/credentials' do
      backend = build(:storage_backend,
                      configuration: { 'access_key' => 'AKID', 'bucket' => 'my-bucket' })
      masked = backend.masked_configuration
      expect(masked['access_key']).to eq('********')
      expect(masked['bucket']).to eq('my-bucket')
    end
  end

  describe '#adapter' do
    it 'delegates to StorageManager.adapter_for' do
      backend = build(:storage_backend)
      adapter = instance_double(StorageAdapters::LocalStorageAdapter)
      allow(StorageManager).to receive(:adapter_for).with(backend).and_return(adapter)

      expect(backend.adapter).to eq(adapter)
    end
  end

  describe '#test_connection' do
    it 'returns the adapter result when the connection succeeds' do
      backend = build(:storage_backend)
      adapter = instance_double(StorageAdapters::LocalStorageAdapter, test_connection: { success: true })
      allow(backend).to receive(:adapter).and_return(adapter)

      expect(backend.test_connection).to eq({ success: true })
    end

    it 'rescues errors raised by the adapter and returns a failure hash' do
      backend = build(:storage_backend)
      adapter = instance_double(StorageAdapters::LocalStorageAdapter)
      allow(backend).to receive(:adapter).and_return(adapter)
      allow(adapter).to receive(:test_connection).and_raise(StandardError.new('unreachable'))

      result = backend.test_connection
      expect(result).to eq({ success: false, error: 'unreachable' })
    end
  end
end
