require 'rails_helper'

RSpec.describe StorageAdapters::GcsAdapter, type: :service do
  subject(:adapter) { described_class.new(project_id: 'project-1', bucket: 'assets', acl: acl) }

  let(:acl) { 'private' }
  let(:bucket) { instance_double('Google::Cloud::Storage::Bucket') }
  let(:gcs_file) { instance_double('Google::Cloud::Storage::File') }

  before do
    allow(adapter).to receive(:gcs_bucket).and_return(bucket)
    allow(Rails.logger).to receive(:error)
  end

  describe '#store' do
    it 'creates the file in the bucket' do
      allow(bucket).to receive(:create_file).and_return(instance_double('Google::Cloud::Storage::File', name: 'folder/file.txt'))

      expect(adapter.store(StringIO.new('hello'), 'folder/file.txt')).to eq('folder/file.txt')
    end

    it 'wraps provider failures in a storage error' do
      allow(bucket).to receive(:create_file).and_raise(Google::Cloud::Error.new('boom'))

      expect { adapter.store(StringIO.new('hello'), 'folder/file.txt') }.to raise_error(StorageAdapters::StorageError, /GCS store failed/)
    end
  end

  describe '#delete' do
    it 'deletes the file when it exists' do
      allow(bucket).to receive(:file).with('folder/file.txt').and_return(gcs_file)
      allow(gcs_file).to receive(:delete)

      expect(adapter.delete('folder/file.txt')).to be_nil
      expect(gcs_file).to have_received(:delete)
    end

    it 'returns nil when the file is missing' do
      allow(bucket).to receive(:file).and_raise(Google::Cloud::NotFoundError.new('missing'))

      expect(adapter.delete('missing.txt')).to be_nil
    end
  end

  describe '#url' do
    it 'returns a signed URL for private buckets' do
      allow(adapter).to receive(:presign_url).with('folder/file.txt', expires_in: 86_400).and_return('signed-url')

      expect(adapter.url('folder/file.txt')).to eq('signed-url')
    end

    it 'returns the public bucket URL when configured' do
      public_adapter = described_class.new(bucket: 'assets', acl: 'public-read')
      allow(public_adapter).to receive(:gcs_bucket).and_return(bucket)

      expect(public_adapter.url('folder/file.txt')).to eq('https://storage.googleapis.com/assets/folder/file.txt')
    end
  end

  describe '#presign_url' do
    it 'signs the URL and appends a download filename when requested' do
      allow(bucket).to receive(:file).and_return(gcs_file)
      allow(gcs_file).to receive(:signed_url).and_return('https://example.com/file?foo=bar')

      url = adapter.presign_url('folder/file.txt', filename: 'download.txt')

      expect(url).to include('response-content-disposition=attachment%3B+filename%3D%22download.txt%22')
    end

    it 'raises when the file cannot be found for presigning' do
      allow(bucket).to receive(:file).and_return(nil)

      expect { adapter.presign_url('missing.txt') }.to raise_error(StorageAdapters::StorageError, /not found for presigning/)
    end
  end

  describe '#supports_presigned_urls?' do
    it 'returns true' do
      expect(adapter.supports_presigned_urls?).to be(true)
    end
  end

  describe '#exists?' do
    it 'returns true when the file exists' do
      allow(bucket).to receive(:file).and_return(gcs_file)

      expect(adapter.exists?('folder/file.txt')).to be(true)
    end

    it 'returns false when the provider raises an error' do
      allow(bucket).to receive(:file).and_raise(Google::Cloud::Error.new('boom'))

      expect(adapter.exists?('folder/file.txt')).to be(false)
    end
  end

  describe '#copy' do
    it 'copies the file and returns the destination path' do
      allow(bucket).to receive(:file).with('from.txt').and_return(gcs_file)
      allow(gcs_file).to receive(:copy).with('to.txt')

      expect(adapter.copy('from.txt', 'to.txt')).to eq('to.txt')
    end
  end

  describe '#metadata' do
    it 'returns normalized file metadata' do
      allow(bucket).to receive(:file).and_return(gcs_file)
      allow(gcs_file).to receive_messages(size: 12, content_type: 'text/plain', etag: 'etag', updated_at: Time.current, metadata: { 'foo' => 'bar' })

      expect(adapter.metadata('folder/file.txt')).to include(size: 12, content_type: 'text/plain', etag: 'etag', metadata: { 'foo' => 'bar' })
    end

    it 'returns nil when the file is missing' do
      allow(bucket).to receive(:file).and_return(nil)

      expect(adapter.metadata('missing.txt')).to be_nil
    end
  end

  describe '#list' do
    it 'lists bucket files' do
      allow(bucket).to receive(:files).with(prefix: 'folder/', max: 100).and_return([
        instance_double('Google::Cloud::Storage::File', name: 'folder/file.txt', size: 9, updated_at: Time.current, etag: 'etag')
      ])

      expect(adapter.list(prefix: 'folder/')).to eq([{ key: 'folder/file.txt', size: 9, last_modified: bucket.files(prefix: 'folder/', max: 100).first.updated_at, etag: 'etag' }])
    end

    it 'logs and returns an empty array when listing fails' do
      allow(bucket).to receive(:files).and_raise(Google::Cloud::Error.new('boom'))

      expect(adapter.list).to eq([])
      expect(Rails.logger).to have_received(:error).with(/list failed/)
    end
  end

  describe '#test_connection' do
    it 'returns success when the bucket lookup works' do
      expect(adapter.test_connection).to eq(success: true, message: "Connected to GCS bucket 'assets' in project 'project-1'")
    end

    it 'maps not found errors' do
      allow(adapter).to receive(:gcs_bucket).and_raise(Google::Cloud::NotFoundError.new('missing'))

      expect(adapter.test_connection).to eq(success: false, error: "Bucket 'assets' not found in project 'project-1'.")
    end

    it 'maps permission errors' do
      allow(adapter).to receive(:gcs_bucket).and_raise(Google::Cloud::PermissionDeniedError.new('denied'))

      expect(adapter.test_connection).to eq(success: false, error: 'Permission denied. Ensure the service account has Storage Object Admin role.')
    end
  end

  describe 'private helpers' do
    it 'normalizes the configured ACL' do
      expect(adapter.send(:gcs_acl, 'public')).to eq('publicRead')
      expect(adapter.send(:gcs_acl, 'private')).to be_nil
      expect(adapter.send(:gcs_acl, 'custom')).to eq('custom')
    end
  end
end
