require 'rails_helper'

RSpec.describe StorageAdapters::BaseAdapter, type: :service do
  subject(:adapter) { described_class.new(access_key: 'key', cdn_base_url: 'https://cdn.example.com') }

  describe '#initialize' do
    it 'stringifies configuration keys' do
      expect(adapter.config).to eq('access_key' => 'key', 'cdn_base_url' => 'https://cdn.example.com')
    end

    it 'ignores non-hash configuration values' do
      expect(described_class.new('raw-string').config).to eq({})
    end
  end

  describe 'StorageError constant' do
    it 'does not redefine StorageError when the file is loaded again' do
      original = StorageAdapters::StorageError

      load Rails.root.join('app/services/storage_adapters/base_adapter.rb')

      expect(StorageAdapters::StorageError).to equal(original)
    end
  end

  describe 'abstract methods' do
    it { expect { adapter.store(StringIO.new('data'), 'path') }.to raise_error(NotImplementedError) }
    it { expect { adapter.delete('path') }.to raise_error(NotImplementedError) }
    it { expect { adapter.url('path') }.to raise_error(NotImplementedError) }
    it { expect { adapter.presign_url('path') }.to raise_error(NotImplementedError) }
    it { expect { adapter.exists?('path') }.to raise_error(NotImplementedError) }
    it { expect { adapter.copy('from', 'to') }.to raise_error(NotImplementedError) }
    it { expect { adapter.metadata('path') }.to raise_error(NotImplementedError) }
    it { expect { adapter.list }.to raise_error(NotImplementedError) }
    it { expect { adapter.test_connection }.to raise_error(NotImplementedError) }
  end

  describe '#move' do
    it 'copies then deletes the source path' do
      allow(adapter).to receive(:copy).with('from', 'to').and_return('to')
      allow(adapter).to receive(:delete).with('from')

      expect(adapter.move('from', 'to')).to eq('to')
      expect(adapter).to have_received(:delete).with('from')
    end
  end

  describe '#supports_presigned_urls?' do
    it 'is false by default' do
      expect(adapter.supports_presigned_urls?).to be(false)
    end
  end

  describe '#provider_name' do
    it 'derives the provider from the class name' do
      expect(StorageAdapters::S3Adapter.new.provider_name).to eq('s3')
    end
  end

  describe '#cdn_url' do
    it 'prefers the configured CDN base url' do
      expect(adapter.cdn_url('assets/file.jpg')).to eq('https://cdn.example.com/assets/file.jpg')
    end

    it 'falls back to #url when no CDN base is configured' do
      plain_adapter = described_class.new(cdn_base_url: '')
      allow(plain_adapter).to receive(:url).with('assets/file.jpg').and_return('https://origin.example.com/assets/file.jpg')

      expect(plain_adapter.cdn_url('assets/file.jpg')).to eq('https://origin.example.com/assets/file.jpg')
    end
  end

  describe '#trigger_ai_enrichment' do
    let(:redis) { instance_double(Redis, publish: true) }

    before do
      allow(Redis).to receive(:new).and_return(redis)
      allow(Rails.logger).to receive(:warn)
    end

    it 'publishes an enrichment event when an asset uuid is present' do
      adapter.trigger_ai_enrichment(asset_uuid: 'asset-1', storage_path: 'files/hero.jpg', content_type: 'image/jpeg')

      expect(redis).to have_received(:publish) do |channel, payload|
        expect(channel).to eq('ai_gateway_events')
        expect(JSON.parse(payload)).to include(
          'event' => 'asset.needs_embedding',
          'asset_uuid' => 'asset-1',
          'provider' => adapter.provider_name,
          'storage_path' => 'files/hero.jpg',
          'content_type' => 'image/jpeg'
        )
      end
    end

    it 'returns early when no asset uuid is supplied' do
      adapter.trigger_ai_enrichment(storage_path: 'files/hero.jpg')

      expect(redis).not_to have_received(:publish)
    end

    it 'logs and swallows publish failures' do
      allow(redis).to receive(:publish).and_raise(StandardError, 'offline')

      expect { adapter.trigger_ai_enrichment(asset_uuid: 'asset-1') }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/AI enrichment trigger failed: offline/)
    end
  end
end
