require 'rails_helper'

RSpec.describe IngestionAdapters::Base, type: :service do
  subject(:adapter) { described_class.new(batch, endpoint: 'https://dam.example.com/', auth_token: 'secret') }

  let(:batch) { build_stubbed(:ingestion_batch) }

  describe '#initialize' do
    it 'stores the batch and stringifies credential keys' do
      expect(adapter.batch).to eq(batch)
      expect(adapter.credentials).to eq('endpoint' => 'https://dam.example.com/', 'auth_token' => 'secret')
    end
  end

  describe 'abstract interface' do
    it 'raises for #fetch_next_chunk' do
      expect { adapter.fetch_next_chunk }.to raise_error(NotImplementedError)
    end

    it 'raises for #download_and_stream' do
      expect { adapter.download_and_stream('file') }.to raise_error(NotImplementedError)
    end

    it 'raises for #test_connection' do
      expect { adapter.test_connection }.to raise_error(NotImplementedError)
    end
  end

  describe 'protected helpers' do
    describe '#get_json' do
      it 'performs an authenticated GET and parses the JSON response' do
        http = instance_double(Net::HTTP)
        response = Net::HTTPOK.new('1.1', '200', 'OK')
        allow(response).to receive(:body).and_return('{"ok":true}')

        allow(Net::HTTP).to receive(:start).with('dam.example.com', 443, use_ssl: true).and_yield(http)
        allow(http).to receive(:request) do |request|
          expect(request['Authorization']).to eq('Bearer secret')
          expect(request['Accept']).to eq('application/json')
          response
        end

        expect(adapter.send(:get_json, 'https://dam.example.com/assets')).to eq('ok' => true)
      end

      it 'raises for non-success responses' do
        http = instance_double(Net::HTTP)
        response = Net::HTTPBadRequest.new('1.1', '400', 'Bad Request')
        allow(response).to receive(:body).and_return('failure')

        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:request).and_return(response)

        expect do
          adapter.send(:get_json, 'https://dam.example.com/assets')
        end.to raise_error('HTTP 400 from https://dam.example.com/assets: failure')
      end
    end

    describe '#stream_http_file' do
      let(:tempfile) do
        instance_double(Tempfile, binmode: true, write: true, rewind: true, path: 'spec/fixtures/files/streamed.bin', close: true)
      end

      it 'streams the response body into a tempfile and yields chunks' do
        http = instance_double(Net::HTTP)
        response = instance_double(Net::HTTPResponse)
        chunks = []

        allow(Tempfile).to receive(:new).and_return(tempfile)
        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:request) do |request, &block|
          expect(request['Authorization']).to eq('Bearer secret')
          block.call(response)
        end
        allow(response).to receive(:read_body).and_yield('abc').and_yield('def')

        path = adapter.send(:stream_http_file, 'https://dam.example.com/file.jpg', '.jpg') { |chunk| chunks << chunk }

        expect(path).to eq('spec/fixtures/files/streamed.bin')
        expect(chunks).to eq(%w[abc def])
        expect(tempfile).to have_received(:write).with('abc')
        expect(tempfile).to have_received(:write).with('def')
      end
    end

    it 'builds default bearer headers' do
      expect(adapter.send(:default_headers)).to include(
        'Authorization' => 'Bearer secret',
        'Accept' => 'application/json',
        'Content-Type' => 'application/json'
      )
    end

    it 'normalizes the endpoint by removing a trailing slash' do
      expect(adapter.send(:endpoint)).to eq('https://dam.example.com')
    end
  end
end
