require 'rails_helper'

RSpec.describe StorageAdapters::LocalStorageAdapter, type: :service do
  subject(:adapter) { described_class.new }

  let(:root_path) { Rails.root.join('spec/fixtures/local_storage_adapter') }

  before do
    stub_const('StorageAdapters::LocalStorageAdapter::ROOT', -> { root_path })
    FileUtils.rm_rf(root_path)
  end

  after do
    FileUtils.rm_rf(root_path)
  end

  describe '#store' do
    it 'writes the file contents to the configured root path' do
      result = adapter.store(StringIO.new('hello world'), 'nested/file.txt')

      expect(result).to eq('nested/file.txt')
      expect(root_path.join('nested/file.txt').read).to eq('hello world')
    end
  end

  describe '#delete' do
    it 'removes an existing file' do
      root_path.join('nested').mkpath
      root_path.join('nested/file.txt').write('content')

      adapter.delete('nested/file.txt')

      expect(root_path.join('nested/file.txt')).not_to exist
    end
  end

  describe '#url' do
    it 'returns the local asset path' do
      expect(adapter.url('nested/file.txt')).to eq('/api/v1/assets/local/nested/file.txt')
    end
  end

  describe '#presign_url' do
    it 'returns a signed URL when the message verifier succeeds' do
      verifier = instance_double(ActiveSupport::MessageVerifier, generate: 'signed-token')
      allow(Rails.application).to receive(:message_verifier).with(:storage_presign).and_return(verifier)

      url = adapter.presign_url('nested/file.txt', expires_in: 60, filename: 'file.txt')

      expect(url).to include('/api/v1/assets/local/nested/file.txt?')
      expect(url).to include('token=signed-token')
      expect(url).to include('filename=file.txt')
    end

    it 'falls back to the plain URL when signing fails' do
      verifier = instance_double(ActiveSupport::MessageVerifier)
      allow(verifier).to receive(:generate).and_raise(StandardError, 'bad verifier')
      allow(Rails.application).to receive(:message_verifier).with(:storage_presign).and_return(verifier)
      allow(Rails.logger).to receive(:warn)

      expect(adapter.presign_url('nested/file.txt')).to eq('/api/v1/assets/local/nested/file.txt')
      expect(Rails.logger).to have_received(:warn).with(/Presign failed/)
    end
  end

  describe '#exists?' do
    it 'checks file existence' do
      root_path.join('nested').mkpath
      root_path.join('nested/file.txt').write('content')

      expect(adapter.exists?('nested/file.txt')).to be(true)
      expect(adapter.exists?('missing.txt')).to be(false)
    end
  end

  describe '#copy' do
    it 'copies the file into a new location' do
      root_path.join('nested').mkpath
      root_path.join('nested/file.txt').write('content')

      expect(adapter.copy('nested/file.txt', 'copies/file.txt')).to eq('copies/file.txt')
      expect(root_path.join('copies/file.txt').read).to eq('content')
    end
  end

  describe '#metadata' do
    it 'returns file metadata for an existing file' do
      root_path.join('nested').mkpath
      file_path = root_path.join('nested/file.txt')
      file_path.write('content')

      metadata = adapter.metadata('nested/file.txt')

      expect(metadata).to include(size: 7, metadata: {})
      expect(metadata[:etag]).to be_present
      expect(metadata[:content_type]).to eq('text/plain')
    end

    it 'returns nil when the file does not exist' do
      expect(adapter.metadata('missing.txt')).to be_nil
    end
  end

  describe '#list' do
    it 'lists files under the given prefix' do
      root_path.join('assets/sub').mkpath
      root_path.join('assets/one.txt').write('one')
      root_path.join('assets/sub/two.txt').write('two')

      result = adapter.list(prefix: 'assets', limit: 10)

      expect(result.map { |entry| entry[:key] }).to contain_exactly('assets/one.txt', 'assets/sub/two.txt')
    end
  end

  describe '#test_connection' do
    it 'creates the storage root if needed' do
      expect(adapter.test_connection).to include(success: true)
      expect(root_path).to exist
    end
  end

  describe '#supports_presigned_urls?' do
    it 'returns true' do
      expect(adapter.supports_presigned_urls?).to be(true)
    end
  end
end
