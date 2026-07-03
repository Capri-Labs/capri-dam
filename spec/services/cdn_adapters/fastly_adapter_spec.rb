require 'rails_helper'

RSpec.describe CdnAdapters::FastlyAdapter, type: :service do
  subject(:adapter) { described_class.new(api_key: 'token', service_id: 'svc-1', dictionary_id: 'dict-1') }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe '#purge_tag' do
    it 'issues a soft purge by default' do
      stub_request(:post, 'https://api.fastly.com/service/svc-1/purge/asset-1')
        .with(headers: { 'Fastly-Key' => 'token', 'Fastly-Soft-Purge' => '1' })
        .to_return(status: 200, body: '{}')

      expect(adapter.purge_tag('asset-1')).to be(true)
    end
  end

  describe '#purge_batch' do
    it 'returns true for an empty tag list' do
      expect(adapter.purge_batch([])).to be(true)
    end

    it 'submits batch surrogate keys' do
      stub_request(:post, 'https://api.fastly.com/service/svc-1/purge')
        .with(body: { surrogate_keys: %w[a b] }.to_json)
        .to_return(status: 200, body: '{}')

      expect(adapter.purge_batch(%w[a b], soft_purge: false)).to be(true)
    end
  end

  describe '#sync_metadata' do
    it 'stores metadata in the configured edge dictionary' do
      stub_request(:put, 'https://api.fastly.com/service/svc-1/dictionary/dict-1/item/asset-1')
        .with(body: 'item_value=%7B%22status%22%3A%22ready%22%7D')
        .to_return(status: 200, body: '{}')

      expect(adapter.sync_metadata('asset-1', '{"status":"ready"}')).to be(true)
    end

    it 'returns false on request failures' do
      allow(Net::HTTP).to receive(:start).and_raise(Net::ReadTimeout)

      expect(adapter.sync_metadata('asset-1', '{}')).to be(false)
    end

    it "returns false for non-success HTTP responses" do
      stub_request(:put, "https://api.fastly.com/service/svc-1/dictionary/dict-1/item/asset-1")
        .to_return(status: 500, body: "nope")

      expect(adapter.sync_metadata("asset-1", "{}")).to be(false)
    end
  end
end
