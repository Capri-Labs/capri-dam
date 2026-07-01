require 'rails_helper'

RSpec.describe RedisTokenManager, type: :service do
  describe '.fetch' do
    let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(cache_store)
      allow(Rails.logger).to receive(:info)
    end

    it 'caches generated tokens by domain and service' do
      generator = instance_double(Proc)
      allow(generator).to receive(:call).and_return('token-123')

      first = described_class.fetch('cdn', 'fastly') { generator.call }
      second = described_class.fetch('cdn', 'fastly') { generator.call }

      expect(first).to eq('token-123')
      expect(second).to eq('token-123')
      expect(generator).to have_received(:call).once
    end

    it 'raises when the generated token is blank' do
      expect do
        described_class.fetch('cdn', 'fastly') { '' }
      end.to raise_error('Vault Error: Failed to generate cdn token for fastly')
    end
  end

  describe '.revoke' do
    it 'deletes the cached token' do
      cache_store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(cache_store)
      allow(Rails.logger).to receive(:info)
      cache_store.write('dam:vault:cdn:fastly', 'token-123')

      described_class.revoke('cdn', 'fastly')

      expect(cache_store.read('dam:vault:cdn:fastly')).to be_nil
    end
  end

  describe '.revoke_domain' do
    let(:redis) { instance_double(Redis) }

    before do
      allow(Redis).to receive(:new).and_return(redis)
      allow(Rails.logger).to receive(:warn)
    end

    it 'scans and deletes all keys for the domain' do
      allow(redis).to receive(:scan).and_return(
        [ '1', [ 'dam:vault:cdn:one', 'dam:vault:cdn:two' ] ],
        [ '0', [] ]
      )
      allow(redis).to receive(:del)

      described_class.revoke_domain('cdn')

      expect(redis).to have_received(:del).with('dam:vault:cdn:one', 'dam:vault:cdn:two')
    end
  end
end
