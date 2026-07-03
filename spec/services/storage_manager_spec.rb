require 'rails_helper'

RSpec.describe StorageManager, type: :service do
  after { described_class.reset_active_adapter! }

  describe '.adapter_for' do
    it 'returns local storage when no backend is configured' do
      expect(described_class.adapter_for(nil)).to be_a(StorageAdapters::LocalStorageAdapter)
    end

    it 'instantiates the provider adapter with stringified configuration' do
      backend = instance_double(StorageBackend, provider_type: 'azure', configuration: { container: 'assets' })
      adapter = instance_double(StorageAdapters::AzureAdapter)
      expect(StorageAdapters::AzureAdapter).to receive(:new).with({ 'container' => 'assets' }).and_return(adapter)

      expect(described_class.adapter_for(backend)).to eq(adapter)
    end

    it 'raises for unknown providers' do
      backend = instance_double(StorageBackend, provider_type: 'mystery', configuration: {})

      expect { described_class.adapter_for(backend) }.to raise_error(ArgumentError, /Unknown storage provider/)
    end
  end

  describe '.active_adapter and .store!' do
    it 'builds, caches, resets, stores, and triggers AI enrichment with the stored path' do
      adapter = instance_double(StorageAdapters::BaseAdapter)
      allow(Setting).to receive(:get).with('active_storage_provider').and_return('google')
      allow(Setting).to receive(:get).with('storage_config_google').and_return({ bucket: 'assets' })
      allow(StorageAdapters::GcsAdapter).to receive(:new).with({ 'bucket' => 'assets' }).and_return(adapter)
      allow(adapter).to receive(:store).and_return('stored/file.jpg')
      allow(adapter).to receive(:trigger_ai_enrichment)

      expect(described_class.active_adapter).to eq(adapter)
      expect(described_class.active_adapter).to eq(adapter)
      expect(StorageAdapters::GcsAdapter).to have_received(:new).once

      result = described_class.store!(StringIO.new('data'), 'file.jpg', content_type: 'image/jpeg', ai_enrichment: { asset_uuid: 'asset-1' })

      expect(result).to eq('stored/file.jpg')
      expect(adapter).to have_received(:store).with(anything, 'file.jpg', content_type: 'image/jpeg')
      expect(adapter).to have_received(:trigger_ai_enrichment).with(asset_uuid: 'asset-1', storage_path: 'stored/file.jpg', content_type: 'image/jpeg')

      described_class.reset_active_adapter!
      described_class.active_adapter
      expect(StorageAdapters::GcsAdapter).to have_received(:new).twice
    end

    it 'stores files without triggering AI enrichment when no enrichment options are provided' do
      adapter = instance_double(StorageAdapters::BaseAdapter, store: 'stored/file.jpg')
      allow(described_class).to receive(:active_adapter).and_return(adapter)
      allow(adapter).to receive(:trigger_ai_enrichment)

      result = described_class.store!(StringIO.new('data'), 'file.jpg', content_type: 'image/jpeg')

      expect(result).to eq('stored/file.jpg')
      expect(adapter).not_to have_received(:trigger_ai_enrichment)
    end

    it 'falls back to local storage when settings cannot build an adapter' do
      allow(Setting).to receive(:get).and_return(nil)
      allow(Setting).to receive(:get).with('active_storage_provider').and_return('unknown')
      allow(Rails.logger).to receive(:error)

      expect(described_class.active_adapter).to be_a(StorageAdapters::LocalStorageAdapter)
      expect(Rails.logger).to have_received(:error).with(/Failed to build active adapter/)
    end
  end

  describe '.presign_url' do
    it 'uses presign_url when supported and cdn_url otherwise' do
      adapter = instance_double(StorageAdapters::BaseAdapter)
      allow(described_class).to receive(:active_adapter).and_return(adapter)
      allow(adapter).to receive(:supports_presigned_urls?).and_return(true, false)
      allow(adapter).to receive(:presign_url).and_return('signed')
      allow(adapter).to receive(:cdn_url).and_return('cdn')

      expect(described_class.presign_url('a.jpg', expires_in: 60)).to eq('signed')
      expect(described_class.presign_url('a.jpg')).to eq('cdn')
    end
  end

  describe '.migrate_assets!' do
    it 'counts dry-run candidates without reading or writing files' do
      create(:asset_version, properties: { 'storage_path' => 'a.jpg' })
      create(:asset_version, properties: {})
      allow(described_class).to receive(:build_adapter_for_provider).and_return(instance_double(StorageAdapters::BaseAdapter), instance_double(StorageAdapters::BaseAdapter))

      expect(described_class.migrate_assets!(from_provider: 'local', to_provider: 'aws', dry_run: true)).to eq(migrated: 1, failed: [], dry_run: true)
    end

    it 'stores remote file data and records migration failures' do
      ok = create(:asset_version, properties: { 'storage_path' => 'ok.jpg', 'content_type' => 'image/jpeg' })
      bad = create(:asset_version, properties: { 'storage_path' => 'bad.jpg' })
      from_adapter = instance_double(StorageAdapters::BaseAdapter, supports_presigned_urls?: true)
      to_adapter = instance_double(StorageAdapters::BaseAdapter)
      allow(described_class).to receive(:build_adapter_for_provider).and_return(from_adapter, to_adapter)
      allow(from_adapter).to receive(:presign_url).with('ok.jpg', expires_in: 600).and_return('https://files.example.com/ok.jpg')
      allow(from_adapter).to receive(:presign_url).with('bad.jpg', expires_in: 600).and_return('https://files.example.com/bad.jpg')
      stub_request(:get, 'https://files.example.com/ok.jpg').to_return(status: 200, body: 'bytes')
      stub_request(:get, 'https://files.example.com/bad.jpg').to_return(status: 500, body: 'broken')
      allow(to_adapter).to receive(:store).with(anything, 'ok.jpg', content_type: 'image/jpeg').and_return('new/ok.jpg')
      allow(to_adapter).to receive(:store).with(anything, 'bad.jpg', content_type: nil).and_raise(StandardError, 'cannot store')
      allow(Rails.logger).to receive(:error)

      result = described_class.migrate_assets!(from_provider: 'google', to_provider: 'azure')

      expect(result[:migrated]).to eq(1)
      expect(result[:failed]).to contain_exactly(hash_including(version_id: bad.id, path: 'bad.jpg', error: 'cannot store'))
      expect(ok.reload.properties['storage_path']).to eq('new/ok.jpg')
    end

    it 'skips versions whose source file cannot be read' do
      create(:asset_version, properties: { 'storage_path' => 'missing.jpg', 'content_type' => 'image/jpeg' })
      from_adapter = StorageAdapters::LocalStorageAdapter.new({})
      to_adapter = instance_double(StorageAdapters::BaseAdapter)
      allow(described_class).to receive(:build_adapter_for_provider).and_return(from_adapter, to_adapter)
      allow(to_adapter).to receive(:store)
      allow(File).to receive(:exist?).with(Rails.root.join("storage/dam/missing.jpg")).and_return(false)

      result = described_class.migrate_assets!(from_provider: 'local', to_provider: 'aws')

      expect(result).to eq(migrated: 0, failed: [], dry_run: false)
      expect(to_adapter).not_to have_received(:store)
    end
  end

  describe '.load_config_for_provider' do
    it 'returns an empty hash for the local provider' do
      expect(described_class.send(:load_config_for_provider, 'local')).to eq({})
    end
  end

  describe '.read_file_from_adapter' do
    it 'reads local files directly when they exist' do
      adapter = StorageAdapters::LocalStorageAdapter.new({})
      full_path = Rails.root.join("storage/dam/present.jpg")
      allow(File).to receive(:exist?).with(full_path).and_return(true)
      allow(File).to receive(:binread).with(full_path).and_return('bytes')

      expect(described_class.send(:read_file_from_adapter, adapter, 'present.jpg')).to eq('bytes')
    end

    it 'returns nil for missing local files' do
      adapter = StorageAdapters::LocalStorageAdapter.new({})
      full_path = Rails.root.join("storage/dam/missing.jpg")
      allow(File).to receive(:exist?).with(full_path).and_return(false)

      expect(described_class.send(:read_file_from_adapter, adapter, 'missing.jpg')).to be_nil
    end

    it 'uses the adapter url when presigned urls are unsupported' do
      adapter = instance_double(StorageAdapters::BaseAdapter, supports_presigned_urls?: false, url: 'https://files.example.com/plain.jpg')
      allow(Net::HTTP).to receive(:get).with(URI.parse('https://files.example.com/plain.jpg')).and_return('plain-bytes')

      expect(described_class.send(:read_file_from_adapter, adapter, 'plain.jpg')).to eq('plain-bytes')
    end
  end
end
