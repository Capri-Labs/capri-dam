require 'rails_helper'

RSpec.describe CdnAdapters::CloudflareAdapter, type: :service do
  subject(:adapter) do
    described_class.new(
      api_token: 'token',
      zone_id: 'zone-1',
      account_id: 'acct-1',
      kv_namespace: 'ns-1'
    )
  end

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe '#sync_metadata' do
    it 'writes the JSON payload into Cloudflare KV' do
      stub_request(:put, 'https://api.cloudflare.com/client/v4/accounts/acct-1/storage/kv/namespaces/ns-1/values/asset-asset-1')
        .with(headers: { 'Authorization' => 'Bearer token', 'Content-Type' => 'application/json' }, body: '{"status":"ready"}')
        .to_return(status: 200, body: { success: true }.to_json)

      expect(adapter.sync_metadata('asset-1', '{"status":"ready"}')).to be(true)
    end
  end

  describe '#purge_tag' do
    it 'delegates to #purge_batch' do
      expect(adapter).to receive(:purge_batch) do |tags, options|
        expect(tags).to eq(['asset-1'])
        expect(options).to eq(soft: true)
        true
      end

      adapter.purge_tag('asset-1', soft: true)
    end
  end

  describe '#purge_batch' do
    it 'returns true for an empty tag list' do
      expect(adapter.purge_batch([])).to be(true)
    end

    it 'chunks large purges into Cloudflare-sized batches' do
      tags = Array.new(31) { |i| "asset-#{i}" }
      stub_request(:post, 'https://api.cloudflare.com/client/v4/zones/zone-1/purge_cache')
        .to_return(status: 200, body: { success: true }.to_json)

      expect(adapter.purge_batch(tags)).to be(true)
      expect(a_request(:post, 'https://api.cloudflare.com/client/v4/zones/zone-1/purge_cache')).to have_been_made.twice
    end

    it 'returns false when Cloudflare reports a logical error' do
      stub_request(:post, 'https://api.cloudflare.com/client/v4/zones/zone-1/purge_cache')
        .to_return(status: 200, body: { success: false, errors: ['bad tag'] }.to_json)

      expect(adapter.purge_batch(['asset-1'])).to be(false)
    end
  end
end
