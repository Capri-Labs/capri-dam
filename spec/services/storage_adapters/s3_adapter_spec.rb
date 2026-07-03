require 'rails_helper'

RSpec.describe StorageAdapters::S3Adapter, type: :service do
  subject(:adapter) do
    described_class.new(
      access_key: 'key',
      secret_key: 'secret',
      region: 'eu-west-1',
      bucket: 'assets',
      endpoint: endpoint,
      acl: acl
    )
  end

  let(:endpoint) { nil }
  let(:acl) { 'private' }
  let(:client) do
    instance_double(
      Aws::S3::Client,
      put_object: true,
      delete_object: true,
      copy_object: true,
      head_bucket: true
    )
  end
  let(:presigner) { instance_double(Aws::S3::Presigner) }

  before do
    allow(Aws::S3::Client).to receive(:new).and_return(client)
    allow(Aws::S3::Presigner).to receive(:new).with(client: client).and_return(presigner)
    allow(Rails.logger).to receive(:error)
  end

  def aws_error(klass, message = 'boom')
    klass.new(nil, message)
  end

  describe '#store' do
    it 'uploads the object with normalized metadata' do
      expect(adapter.store(StringIO.new('hello'), 'folder/file.txt', metadata: { cache: 1 })).to eq('folder/file.txt')

      expect(client).to have_received(:put_object).with(hash_including(
        bucket: 'assets',
        key: 'folder/file.txt',
        acl: 'private',
        metadata: { 'cache' => '1' }
      ))
    end

    it 'wraps provider errors in a storage error' do
      allow(client).to receive(:put_object).and_raise(aws_error(Aws::S3::Errors::ServiceError))

      expect { adapter.store(StringIO.new('hello'), 'folder/file.txt') }.to raise_error(StorageAdapters::StorageError, /S3 store failed/)
    end
  end

  describe '#delete' do
    it 'deletes the object' do
      expect(adapter.delete('folder/file.txt')).to be(true)
      expect(client).to have_received(:delete_object).with(bucket: 'assets', key: 'folder/file.txt')
    end

    it 'returns nil for a missing key' do
      allow(client).to receive(:delete_object).and_raise(aws_error(Aws::S3::Errors::NoSuchKey))

      expect(adapter.delete('missing.txt')).to be_nil
    end

    it 'wraps provider delete failures in a storage error' do
      allow(client).to receive(:delete_object).and_raise(aws_error(Aws::S3::Errors::ServiceError))

      expect { adapter.delete('folder/file.txt') }.to raise_error(StorageAdapters::StorageError, /S3 delete failed/)
    end
  end

  describe '#url' do
    context 'with a public bucket' do
      let(:acl) { 'public-read' }

      it 'returns the endpoint-based URL when a custom endpoint is configured' do
        public_adapter = described_class.new(bucket: 'assets', endpoint: 'https://objects.example.com', acl: 'public-read')

        expect(public_adapter.url('folder/file.txt')).to eq('https://objects.example.com/assets/folder/file.txt')
      end

      it 'returns the default AWS URL without a custom endpoint' do
        public_adapter = described_class.new(bucket: 'assets', region: 'eu-west-1', acl: 'public-read')

        expect(public_adapter.url('folder/file.txt')).to eq('https://assets.s3.eu-west-1.amazonaws.com/folder/file.txt')
      end
    end

    it 'uses presigning for private buckets' do
      allow(adapter).to receive(:presign_url).with('folder/file.txt', expires_in: 86_400).and_return('signed-url')

      expect(adapter.url('folder/file.txt')).to eq('signed-url')
    end
  end

  describe '#presign_url' do
    it 'creates upload presigns with a content type' do
      allow(presigner).to receive(:presigned_url).and_return('put-url')

      expect(adapter.presign_url('folder/file.txt', method: :put, content_type: 'text/plain')).to eq('put-url')
      expect(presigner).to have_received(:presigned_url).with(:put_object, hash_including(content_type: 'text/plain'))
    end

    it 'omits the content type for upload presigns when none is provided' do
      allow(presigner).to receive(:presigned_url).and_return('put-url')

      expect(adapter.presign_url('folder/file.txt', method: :put)).to eq('put-url')
      expect(presigner).to have_received(:presigned_url).with(:put_object, hash_excluding(:content_type))
    end

    it 'creates download presigns with an optional filename' do
      allow(presigner).to receive(:presigned_url).and_return('get-url')

      expect(adapter.presign_url('folder/file.txt', filename: 'download.txt')).to eq('get-url')
      expect(presigner).to have_received(:presigned_url).with(:get_object, hash_including(response_content_disposition: 'attachment; filename="download.txt"'))
    end

    it 'wraps provider presign failures in a storage error' do
      allow(presigner).to receive(:presigned_url).and_raise(aws_error(Aws::S3::Errors::ServiceError))

      expect { adapter.presign_url('folder/file.txt') }.to raise_error(StorageAdapters::StorageError, /S3 presign failed/)
    end
  end

  describe '#supports_presigned_urls?' do
    it 'returns true' do
      expect(adapter.supports_presigned_urls?).to be(true)
    end
  end

  describe '#exists?' do
    it 'returns true when head_object succeeds' do
      allow(client).to receive(:head_object).and_return(true)

      expect(adapter.exists?('folder/file.txt')).to be(true)
    end

    it 'returns false when the object does not exist' do
      allow(client).to receive(:head_object).and_raise(aws_error(Aws::S3::Errors::NotFound))

      expect(adapter.exists?('missing.txt')).to be(false)
    end
  end

  describe '#copy' do
    it 'copies the object server-side' do
      expect(adapter.copy('from.txt', 'to.txt')).to eq('to.txt')
      expect(client).to have_received(:copy_object).with(hash_including(copy_source: 'assets/from.txt', key: 'to.txt'))
    end

    it 'wraps provider copy failures in a storage error' do
      allow(client).to receive(:copy_object).and_raise(aws_error(Aws::S3::Errors::ServiceError))

      expect { adapter.copy('from.txt', 'to.txt') }.to raise_error(StorageAdapters::StorageError, /S3 copy failed/)
    end
  end

  describe '#metadata' do
    it 'returns normalized head_object metadata' do
      response = instance_double(Aws::S3::Types::HeadObjectOutput,
                                 content_length: 7,
                                 content_type: 'text/plain',
                                 etag: '"etag"',
                                 last_modified: Time.current,
                                 metadata: { 'foo' => 'bar' })
      allow(client).to receive(:head_object).and_return(response)

      expect(adapter.metadata('folder/file.txt')).to include(size: 7, content_type: 'text/plain', etag: 'etag', metadata: { 'foo' => 'bar' })
    end

    it 'preserves a nil etag in metadata responses' do
      response = instance_double(Aws::S3::Types::HeadObjectOutput,
                                 content_length: 7,
                                 content_type: 'text/plain',
                                 etag: nil,
                                 last_modified: Time.current,
                                 metadata: {})
      allow(client).to receive(:head_object).and_return(response)

      expect(adapter.metadata('folder/file.txt')).to include(etag: nil)
    end

    it 'returns nil when the object is missing' do
      allow(client).to receive(:head_object).and_raise(aws_error(Aws::S3::Errors::NoSuchKey))

      expect(adapter.metadata('missing.txt')).to be_nil
    end
  end

  describe '#list' do
    it 'lists object metadata' do
      contents = [ instance_double(Aws::S3::Types::Object, key: 'folder/file.txt', size: 5, last_modified: Time.current, etag: '"etag"') ]
      response = instance_double(Aws::S3::Types::ListObjectsV2Output, contents: contents)
      allow(client).to receive(:list_objects_v2).and_return(response)

      expect(adapter.list(prefix: 'folder/')).to eq([ { key: 'folder/file.txt', size: 5, last_modified: contents.first.last_modified, etag: 'etag' } ])
    end

    it 'keeps nil etags when listing objects' do
      contents = [ instance_double(Aws::S3::Types::Object, key: 'folder/file.txt', size: 5, last_modified: Time.current, etag: nil) ]
      response = instance_double(Aws::S3::Types::ListObjectsV2Output, contents: contents)
      allow(client).to receive(:list_objects_v2).and_return(response)

      expect(adapter.list).to eq([ { key: 'folder/file.txt', size: 5, last_modified: contents.first.last_modified, etag: nil } ])
    end

    it 'logs and returns an empty array on provider failures' do
      allow(client).to receive(:list_objects_v2).and_raise(aws_error(Aws::S3::Errors::ServiceError))

      expect(adapter.list).to eq([])
      expect(Rails.logger).to have_received(:error).with(/list failed/)
    end
  end

  describe '#test_connection' do
    it 'returns a success payload when the bucket exists' do
      allow(client).to receive(:head_bucket).and_return(true)

      expect(adapter.test_connection).to eq(success: true, message: "Connected to 'assets' in eu-west-1")
    end

    it 'maps not found errors to a user-friendly message' do
      allow(client).to receive(:head_bucket).and_raise(aws_error(Aws::S3::Errors::NotFound))

      expect(adapter.test_connection).to eq(success: false, error: "Bucket 'assets' not found.")
    end

    it 'maps forbidden errors to a user-friendly message' do
      allow(client).to receive(:head_bucket).and_raise(aws_error(Aws::S3::Errors::Forbidden))

      expect(adapter.test_connection).to eq(success: false, error: 'Access denied. Check your credentials and bucket policy.')
    end

    it 'returns the underlying error message for unexpected failures' do
      allow(client).to receive(:head_bucket).and_raise(StandardError, 'network timeout')

      expect(adapter.test_connection).to eq(success: false, error: 'network timeout')
    end
  end

  describe 'configuration defaults' do
    it 'falls back to the default region when none is configured' do
      expect(described_class.new(bucket: 'assets').send(:region)).to eq('us-east-1')
    end

    it 'includes a custom endpoint in the client options when configured' do
      expect(described_class.new(bucket: 'assets', endpoint: 'https://objects.example.com').send(:client_options)[:endpoint]).to eq('https://objects.example.com')
    end
  end
end
