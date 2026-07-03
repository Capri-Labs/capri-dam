require 'rails_helper'

RSpec.describe CdnAdapters::AkamaiAdapter, type: :service do
  let(:http_client) { instance_double(Akamai::Edgegrid::HTTP) }

  subject(:adapter) do
    described_class.new(
      host: 'example.luna.akamaiapis.net',
      edgekv_namespace: 'assets',
      client_token: 'client',
      client_secret: 'secret',
      access_token: 'access'
    )
  end

  before do
    allow(Akamai::Edgegrid::HTTP).to receive(:new).and_return(http_client)
    allow(http_client).to receive(:read_timeout=)
    allow(http_client).to receive(:open_timeout=)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe '#sync_metadata' do
    it 'stores metadata in EdgeKV using the EdgeGrid client' do
      response = Net::HTTPCreated.new('1.1', '201', 'Created')
      allow(response).to receive(:body).and_return('{"estimatedSeconds":1}')

      expect(http_client).to receive(:request) do |request|
        expect(request.path).to eq('/edgekv/v1/networks/production/namespaces/assets/groups/assets/items/asset-1')
        expect(request.body).to eq('{"status":"ready"}')
        response
      end

      expect(adapter.sync_metadata('asset-1', '{"status":"ready"}')).to be(true)
    end
  end

  describe '#purge_batch' do
    it 'returns true for an empty tag list' do
      expect(adapter.purge_batch([])).to be(true)
    end

    it 'chunks large invalidations and respects purge options' do
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return('{"estimatedSeconds":2}')
      allow(http_client).to receive(:request).and_return(response)

      tags = Array.new(1001) { |i| "asset-#{i}" }
      expect(adapter.purge_batch(tags, hard_purge: true, network: 'staging')).to be(true)
      expect(http_client).to have_received(:request).twice
    end

    it 'returns false when the EdgeGrid request times out' do
      allow(http_client).to receive(:request).and_raise(Net::OpenTimeout)

      expect(adapter.purge_batch([ 'asset-1' ])).to be(false)
    end

    it 'returns false when Akamai responds with a non-success HTTP status' do
      response = Net::HTTPBadRequest.new('1.1', '400', 'Bad Request')
      allow(response).to receive(:body).and_return('{"detail":"invalid tag"}')
      allow(http_client).to receive(:request).and_return(response)

      expect(adapter.purge_batch([ 'asset-1' ])).to be(false)
      expect(Rails.logger).to have_received(:error).with(include('HTTP failed: 400'))
    end
  end

  describe '#purge_tag' do
    it 'delegates to #purge_batch' do
      expect(adapter).to receive(:purge_batch) do |tags, options|
        expect(tags).to eq([ 'asset-1' ])
        expect(options).to eq(network: 'staging')
        true
      end

      adapter.purge_tag('asset-1', network: 'staging')
    end
  end
end
