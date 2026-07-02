require 'rails_helper'
require 'base64'

RSpec.describe StorageAdapters::AzureAdapter, type: :service do
  subject(:adapter) do
    described_class.new(
      account_name: 'storageacct',
      account_key: Base64.strict_encode64('secret-key'),
      container: 'assets',
      acl: acl,
      cdn_base_url: cdn_base_url
    )
  end

  let(:acl) { 'private' }
  let(:cdn_base_url) { nil }
  let(:blob_client) do
    instance_double(
      'Azure::Storage::Blob::BlobService',
      create_block_blob: true,
      delete_blob: true,
      copy_blob_from_uri: true,
      list_blobs: []
    )
  end

  before do
    allow(adapter).to receive(:blob_client).and_return(blob_client)
    allow(Rails.logger).to receive(:error)
  end

  def azure_error(status, message = 'boom')
    error = Azure::Core::Http::HTTPError.allocate
    allow(error).to receive(:status_code).and_return(status)
    allow(error).to receive(:message).and_return(message)
    error
  end

  describe '#store' do
    it 'creates a block blob and returns the stored path' do
      expect(adapter.store('payload', 'folder/file.txt')).to eq('folder/file.txt')
      expect(blob_client).to have_received(:create_block_blob).with('assets', 'folder/file.txt', 'payload', hash_including(content_type: 'application/octet-stream'))
    end

    it 'wraps provider failures in a storage error' do
      allow(blob_client).to receive(:create_block_blob).and_raise(azure_error(500))

      expect { adapter.store('payload', 'folder/file.txt') }.to raise_error(StorageAdapters::StorageError, /Azure store failed/)
    end
  end

  describe '#delete' do
    it 'deletes the blob' do
      expect(adapter.delete('folder/file.txt')).to be(true)
      expect(blob_client).to have_received(:delete_blob).with('assets', 'folder/file.txt')
    end

    it 'returns nil for a 404 error' do
      allow(blob_client).to receive(:delete_blob).and_raise(azure_error(404))

      expect(adapter.delete('missing.txt')).to be_nil
    end

    it 'wraps non-404 provider failures' do
      allow(blob_client).to receive(:delete_blob).and_raise(azure_error(500, 'down'))

      expect { adapter.delete('folder/file.txt') }.to raise_error(StorageAdapters::StorageError, /Azure delete failed/)
    end
  end

  describe '#url' do
    it 'uses presigning for private containers' do
      allow(adapter).to receive(:presign_url).with('folder/file.txt', expires_in: 86_400).and_return('signed-url')

      expect(adapter.url('folder/file.txt')).to eq('signed-url')
    end

    it 'returns the CDN URL for public containers when configured' do
      public_adapter = described_class.new(account_name: 'storageacct', account_key: Base64.strict_encode64('secret-key'), container: 'assets', acl: 'public-read', cdn_base_url: 'https://cdn.example.com')
      allow(public_adapter).to receive(:blob_client).and_return(blob_client)

      expect(public_adapter.url('folder/file.txt')).to eq('https://cdn.example.com/folder/file.txt')
    end

    it 'returns the native public URL when no CDN is configured' do
      public_adapter = described_class.new(account_name: 'storageacct', account_key: Base64.strict_encode64('secret-key'), container: 'assets', acl: 'public-read')
      allow(public_adapter).to receive(:blob_client).and_return(blob_client)

      expect(public_adapter.url('folder/file.txt')).to eq('https://storageacct.blob.core.windows.net/assets/folder/file.txt')
    end
  end

  describe '#presign_url' do
    it 'builds a SAS URL for uploads and attachments' do
      url = adapter.presign_url('folder/file.txt', method: :put, filename: 'download.txt')

      expect(url).to start_with('https://storageacct.blob.core.windows.net/assets/folder/file.txt?')
      expect(url).to include('sp=cw')
      expect(url).to include('rscd=attachment%3B+filename%3D%22download.txt%22')
    end

    it 'wraps SAS generation failures' do
      allow(Base64).to receive(:decode64).and_raise(ArgumentError, 'bad key')

      expect { adapter.presign_url('folder/file.txt') }.to raise_error(StorageAdapters::StorageError, /Azure SAS generation failed/)
    end
  end

  describe '#supports_presigned_urls?' do
    it 'returns true' do
      expect(adapter.supports_presigned_urls?).to be(true)
    end
  end

  describe '#exists?' do
    it 'returns true when blob properties can be loaded' do
      allow(blob_client).to receive(:get_blob_properties).and_return(true)

      expect(adapter.exists?('folder/file.txt')).to be(true)
    end

    it 'returns false for a missing blob' do
      allow(blob_client).to receive(:get_blob_properties).and_raise(azure_error(404))

      expect(adapter.exists?('missing.txt')).to be(false)
    end

    it 'reraises non-404 lookup failures' do
      error = azure_error(500)
      allow(blob_client).to receive(:get_blob_properties).and_raise(error)

      expect { adapter.exists?('folder/file.txt') }.to raise_error(error)
    end
  end

  describe '#copy' do
    it 'copies the blob server-side' do
      expect(adapter.copy('from.txt', 'to.txt')).to eq('to.txt')
      expect(blob_client).to have_received(:copy_blob_from_uri).with('assets', 'to.txt', 'https://storageacct.blob.core.windows.net/assets/from.txt')
    end

    it 'wraps provider copy failures' do
      allow(blob_client).to receive(:copy_blob_from_uri).and_raise(azure_error(500, 'copy failed'))

      expect { adapter.copy('from.txt', 'to.txt') }.to raise_error(StorageAdapters::StorageError, /Azure copy failed/)
    end
  end

  describe '#metadata' do
    it 'returns normalized blob metadata' do
      blob = instance_double('Blob', properties: { content_length: 12, content_type: 'text/plain', etag: '"etag"', last_modified: Time.current }, metadata: { 'foo' => 'bar' })
      allow(blob_client).to receive(:get_blob_properties).and_return([ nil, blob ])

      expect(adapter.metadata('folder/file.txt')).to include(size: 12, content_type: 'text/plain', etag: 'etag', metadata: { 'foo' => 'bar' })
    end

    it 'returns nil for a missing blob' do
      allow(blob_client).to receive(:get_blob_properties).and_raise(azure_error(404))

      expect(adapter.metadata('missing.txt')).to be_nil
    end

    it 'reraises non-404 metadata failures' do
      error = azure_error(500)
      allow(blob_client).to receive(:get_blob_properties).and_raise(error)

      expect { adapter.metadata('folder/file.txt') }.to raise_error(error)
    end
  end

  describe '#list' do
    it 'lists blobs under the given prefix' do
      blob = instance_double('Blob', name: 'folder/file.txt', properties: { content_length: 1, last_modified: Time.current, etag: '"etag"' })
      allow(blob_client).to receive(:list_blobs).and_return([ blob ])

      expect(adapter.list(prefix: 'folder/')).to eq([ { key: 'folder/file.txt', size: 1, last_modified: blob.properties[:last_modified], etag: 'etag' } ])
    end

    it 'logs and returns an empty array when listing fails' do
      allow(blob_client).to receive(:list_blobs).and_raise(azure_error(500))

      expect(adapter.list).to eq([])
      expect(Rails.logger).to have_received(:error).with(/list failed/)
    end
  end

  describe '#test_connection' do
    it 'returns success when listing blobs succeeds' do
      allow(blob_client).to receive(:list_blobs).and_return([])

      expect(adapter.test_connection).to eq(success: true, message: "Connected to Azure container 'assets' in account 'storageacct'")
    end

    it 'maps 404 errors to a missing container message' do
      allow(blob_client).to receive(:list_blobs).and_raise(azure_error(404))

      expect(adapter.test_connection).to eq(success: false, error: "Container 'assets' not found.")
    end

    it 'maps 403 errors to an access denied message' do
      allow(blob_client).to receive(:list_blobs).and_raise(azure_error(403))

      expect(adapter.test_connection).to eq(success: false, error: 'Access denied. Check your account key.')
    end

    it 'reports other Azure HTTP errors' do
      allow(blob_client).to receive(:list_blobs).and_raise(azure_error(500, 'server down'))

      expect(adapter.test_connection).to eq(success: false, error: 'Azure error 500: server down')
    end

    it 'reports generic connection errors' do
      allow(blob_client).to receive(:list_blobs).and_raise(StandardError, 'offline')

      expect(adapter.test_connection).to eq(success: false, error: 'offline')
    end
  end
end
