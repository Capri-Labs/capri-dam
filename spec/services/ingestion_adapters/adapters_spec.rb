require 'rails_helper'

RSpec.describe 'IngestionAdapters subclasses', type: :service do
  shared_examples 'an HTTP ingestion adapter' do |adapter_class:, credentials:, fetch_response:, expected_identifier:, expected_name:, expected_next_cursor:, expected_has_more:, expected_metadata:, download_id:, expected_download_url:, expected_connection_path:, stream_extension: '.bin', download_response: nil, download_error: nil, fetch_args: [nil, 100]|
    subject(:adapter) { adapter_class.new(nil, credentials) }

    describe '#fetch_next_chunk' do
      it 'maps provider payloads into the normalized file structure' do
        allow(adapter).to receive(:get_json).and_return(fetch_response)

        result = adapter.fetch_next_chunk(*fetch_args)

        expect(result[:files].first).to include(
          identifier: expected_identifier,
          original_name: expected_name,
          metadata: include(expected_metadata)
        )
        expect(result[:next_cursor]).to eq(expected_next_cursor)
        expect(result[:has_more]).to eq(expected_has_more)
      end
    end

    describe '#download_and_stream' do
      it 'streams the remote file through the shared helper' do
        allow(adapter).to receive(:stream_http_file).and_return('downloaded-file')
        allow(adapter).to receive(:get_json).and_return(download_response) if download_response

        if download_error
          expect do
            adapter.download_and_stream(download_id)
          end.to raise_error(download_error)
        else
          expect(adapter.download_and_stream(download_id)).to eq('downloaded-file')
          expect(adapter).to have_received(:stream_http_file).with(expected_download_url, stream_extension)
        end
      end
    end

    describe '#test_connection' do
      it 'returns a success payload when the probe succeeds' do
        expect(adapter).to receive(:get_json).with(expected_connection_path).and_return({})

        expect(adapter.test_connection).to include(success: true)
      end

      it 'returns a failure payload when the probe fails' do
        allow(adapter).to receive(:get_json).and_raise(StandardError, 'unavailable')

        expect(adapter.test_connection).to include(success: false)
      end
    end
  end

  it_behaves_like 'an HTTP ingestion adapter',
                  adapter_class: IngestionAdapters::AemAdapter,
                  credentials: { endpoint: 'https://aem.example.com', auth_token: 'token' },
                  fetch_response: {
                    'entities' => [{
                      'id' => 'asset-1',
                      'name' => 'hero.jpg',
                      'links' => [{ 'rel' => 'self', 'href' => '/content/dam/hero.jpg' }],
                      'properties' => {
                        'dam:size' => 123,
                        'dc:title' => 'Hero',
                        'dc:description' => 'Homepage asset',
                        'cq:tags' => ['marketing'],
                        'dc:creator' => 'Jane',
                        'jcr:created' => '2026-01-01',
                        'dam:mimeType' => 'image/jpeg'
                      }
                    }]
                  },
                  expected_identifier: '/content/dam/hero.jpg',
                  expected_name: 'hero.jpg',
                  expected_next_cursor: '1',
                  expected_has_more: false,
                  expected_metadata: { 'title' => 'Hero', 'creator' => 'Jane' },
                  download_id: '/content/dam/hero.jpg',
                  expected_download_url: 'https://aem.example.com/content/dam/hero.jpg/jcr:content/renditions/original',
                  expected_connection_path: 'https://aem.example.com/api/assets/content/dam.json?count=1',
                  stream_extension: '.jpg'

  it_behaves_like 'an HTTP ingestion adapter',
                  adapter_class: IngestionAdapters::AprimoAdapter,
                  credentials: { endpoint: 'https://aprimo.example.com', auth_token: 'token' },
                  fetch_response: {
                    'items' => [{
                      'id' => 'aprimo-1', 'fileSize' => 321, 'fileName' => 'brochure.pdf',
                      'title' => 'Brochure', 'description' => 'Q3 brochure',
                      'tags' => [{ 'name' => 'print' }], 'mimeType' => 'application/pdf',
                      'createdOn' => '2026-01-01', 'modifiedOn' => '2026-01-02', 'recordId' => 'record-1'
                    }]
                  },
                  expected_identifier: 'aprimo-1',
                  expected_name: 'brochure.pdf',
                  expected_next_cursor: '1',
                  expected_has_more: false,
                  expected_metadata: { 'title' => 'Brochure', 'record_id' => 'record-1' },
                  download_id: 'aprimo-1',
                  download_response: { 'downloadUrl' => 'https://downloads.example.com/aprimo-1' },
                  expected_download_url: 'https://downloads.example.com/aprimo-1',
                  expected_connection_path: 'https://aprimo.example.com/api/dam/v1/assets?limit=1'

  it_behaves_like 'an HTTP ingestion adapter',
                  adapter_class: IngestionAdapters::BrandfolderAdapter,
                  credentials: { endpoint: 'https://brandfolder.example.com', auth_token: 'token', brandfolder_key: 'bf-key' },
                  fetch_response: {
                    'data' => [{
                      'id' => 'bf-1',
                      'attributes' => { 'file_size' => 456, 'name' => 'logo.svg', 'description' => 'Primary logo', 'tags' => ['brand'], 'created_at' => '2026-01-01', 'updated_at' => '2026-01-02' },
                      'relationships' => { 'attachments' => { 'data' => [{ 'id' => 'attachment-1' }] } }
                    }],
                    'meta' => { 'total_pages' => 1 }
                  },
                  expected_identifier: 'bf-1',
                  expected_name: 'logo.svg',
                  expected_next_cursor: '2',
                  expected_has_more: false,
                  expected_metadata: { 'title' => 'logo.svg', 'description' => 'Primary logo' },
                  download_id: 'bf-1',
                  download_response: { 'data' => [{ 'attributes' => { 'url' => 'https://downloads.example.com/logo.svg' } }] },
                  expected_download_url: 'https://downloads.example.com/logo.svg',
                  expected_connection_path: 'https://brandfolder.example.com/api/v4/brandfolders/bf-key?fields=name'

  it_behaves_like 'an HTTP ingestion adapter',
                  adapter_class: IngestionAdapters::BynderAdapter,
                  credentials: { endpoint: 'https://company.bynder.com', auth_token: 'token' },
                  fetch_response: [{
                    'id' => 'bynder-1', 'fileSize' => 789, 'name' => 'launch.mp4', 'description' => 'Launch video',
                    'tags' => ['video'], 'dateCreated' => '2026-01-01', 'dateModified' => '2026-01-02',
                    'extensions' => ['mp4'], 'copyright' => 'ACME', 'campaigns' => ['Spring']
                  }],
                  expected_identifier: 'bynder-1',
                  expected_name: 'launch.mp4',
                  expected_next_cursor: '2',
                  expected_has_more: false,
                  expected_metadata: { 'title' => 'launch.mp4', 'copyright' => 'ACME' },
                  download_id: 'bynder-1',
                  download_response: { 's3_file' => 'https://downloads.example.com/bynder-1' },
                  expected_download_url: 'https://downloads.example.com/bynder-1',
                  expected_connection_path: 'https://company.bynder.com/api/v4/account/'

  it_behaves_like 'an HTTP ingestion adapter',
                  adapter_class: IngestionAdapters::CantoAdapter,
                  credentials: { endpoint: 'https://canto.example.com', auth_token: 'token' },
                  fetch_response: {
                    'results' => [{
                      'id' => 'canto-1', 'size' => 654, 'name' => 'poster.psd', 'description' => 'Poster',
                      'tag' => ['design'], 'contentType' => 'image/vnd.adobe.photoshop',
                      'created' => '2026-01-01', 'lastModified' => '2026-01-02', 'scheme' => 'Default', 'owner' => 'owner'
                    }],
                    'found' => 1
                  },
                  expected_identifier: 'canto-1',
                  expected_name: 'poster.psd',
                  expected_next_cursor: '1',
                  expected_has_more: false,
                  expected_metadata: { 'title' => 'poster.psd', 'owner' => 'owner' },
                  download_id: 'canto-1',
                  download_response: { 'url' => 'https://downloads.example.com/canto-1' },
                  expected_download_url: 'https://downloads.example.com/canto-1',
                  expected_connection_path: 'https://canto.example.com/api/v1/tree'

  it_behaves_like 'an HTTP ingestion adapter',
                  adapter_class: IngestionAdapters::CloudinaryAdapter,
                  credentials: { cloud_name: 'demo', access_key: 'key', secret_key: 'secret' },
                  fetch_response: {
                    'resources' => [{
                      'public_id' => 'folder/photo', 'bytes' => 222, 'format' => 'jpg',
                      'width' => 100, 'height' => 50, 'created_at' => '2026-01-01', 'folder' => 'folder', 'tags' => ['featured']
                    }],
                    'next_cursor' => 'cursor-2'
                  },
                  expected_identifier: 'folder/photo',
                  expected_name: 'folder/photo.jpg',
                  expected_next_cursor: 'cursor-2',
                  expected_has_more: true,
                  expected_metadata: { 'title' => 'photo', 'folder' => 'folder' },
                  download_id: 'folder/photo.jpg',
                  expected_download_url: 'https://res.cloudinary.com/demo/image/upload/folder/photo.jpg',
                  expected_connection_path: 'https://api.cloudinary.com/v1_1/demo/usage',
                  stream_extension: '.jpg'

  it_behaves_like 'an HTTP ingestion adapter',
                  adapter_class: IngestionAdapters::ExtensisAdapter,
                  credentials: { endpoint: 'https://portfolio.example.com', auth_token: 'token' },
                  fetch_response: {
                    'assets' => [{
                      'id' => 'ext-1', 'file_size' => 2048, 'filename' => 'catalog.png', 'title' => 'Catalog',
                      'description' => 'Catalog cover', 'keywords' => ['catalog'], 'mime_type' => 'image/png',
                      'created_at' => '2026-01-01', 'updated_at' => '2026-01-02', 'catalog_name' => 'Main'
                    }],
                    'total_count' => 1
                  },
                  expected_identifier: 'ext-1',
                  expected_name: 'catalog.png',
                  expected_next_cursor: '2',
                  expected_has_more: false,
                  expected_metadata: { 'title' => 'Catalog', 'catalog' => 'Main' },
                  download_id: 'ext-1',
                  expected_download_url: 'https://portfolio.example.com/api/v1/assets/ext-1/download',
                  expected_connection_path: 'https://portfolio.example.com/api/v1/assets?per_page=1'

  it_behaves_like 'an HTTP ingestion adapter',
                  adapter_class: IngestionAdapters::MediaValetAdapter,
                  credentials: { endpoint: 'https://api.mediavalet.com', auth_token: 'token' },
                  fetch_response: {
                    'payload' => {
                      'assets' => [{
                        'id' => 'mv-1',
                        'attributes' => {
                          'fileSize' => 333, 'filename' => 'clip.mov', 'title' => 'Clip', 'description' => 'Media clip',
                          'keywords' => ['media'], 'mediaType' => 'video/quicktime', 'createdAt' => '2026-01-01',
                          'modifiedAt' => '2026-01-02', 'categoryName' => 'Campaign'
                        }
                      }],
                      'total' => 1
                    }
                  },
                  expected_identifier: 'mv-1',
                  expected_name: 'clip.mov',
                  expected_next_cursor: '2',
                  expected_has_more: false,
                  expected_metadata: { 'title' => 'Clip', 'category' => 'Campaign' },
                  download_id: 'mv-1',
                  download_response: { 'payload' => { 'downloadUrl' => 'https://downloads.example.com/mv-1' } },
                  expected_download_url: 'https://downloads.example.com/mv-1',
                  expected_connection_path: 'https://api.mediavalet.com/api/v1.4/categories?pageSize=1'

  it_behaves_like 'an HTTP ingestion adapter',
                  adapter_class: IngestionAdapters::NuxeoAdapter,
                  credentials: { endpoint: 'https://nuxeo.example.com/nuxeo', auth_token: 'token' },
                  fetch_response: {
                    'entries' => [{
                      'uid' => 'nx-1', 'title' => 'Asset',
                      'properties' => {
                        'file:content' => { 'length' => 1024, 'name' => 'asset.jpg', 'mime-type' => 'image/jpeg' },
                        'dc:title' => 'Asset', 'dc:description' => 'Desc', 'dc:subjects' => ['news'],
                        'dc:creator' => 'Jane', 'dc:created' => '2026-01-01', 'dc:modified' => '2026-01-02'
                      }
                    }],
                    'isLastPageAvailable' => true
                  },
                  expected_identifier: 'nx-1',
                  expected_name: 'asset.jpg',
                  expected_next_cursor: '1',
                  expected_has_more: false,
                  expected_metadata: { 'title' => 'Asset', 'creator' => 'Jane' },
                  download_id: 'nx-1',
                  expected_download_url: 'https://nuxeo.example.com/nuxeo/api/v1/id/nx-1/@blob/file:content',
                  expected_connection_path: 'https://nuxeo.example.com/nuxeo/api/v1/query?query=SELECT+*+FROM+Document&pageSize=1'

  it_behaves_like 'an HTTP ingestion adapter',
                  adapter_class: IngestionAdapters::SharepointAdapter,
                  credentials: { endpoint: 'https://graph.microsoft.com/v1.0/drives/drive-1', auth_token: 'token', folder_path: 'root' },
                  fetch_response: {
                    'value' => [{
                      'id' => 'sp-1', 'name' => 'proposal.docx', 'size' => 128,
                      'file' => { 'mimeType' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' },
                      'createdDateTime' => '2026-01-01', 'lastModifiedDateTime' => '2026-01-02',
                      'parentReference' => { 'path' => '/drives/drive-1/root:' }
                    }],
                    '@odata.nextLink' => 'https://graph.microsoft.com/v1.0/next-page'
                  },
                  expected_identifier: 'sp-1',
                  expected_name: 'proposal.docx',
                  expected_next_cursor: 'https://graph.microsoft.com/v1.0/next-page',
                  expected_has_more: true,
                  expected_metadata: { 'title' => 'proposal.docx', 'folder' => '/drives/drive-1/root:' },
                  download_id: 'sp-1',
                  expected_download_url: 'https://graph.microsoft.com/v1.0/drives/drive-1/items/sp-1/content',
                  expected_connection_path: 'https://graph.microsoft.com/v1.0/drives/drive-1/root?$select=id,name'

  it_behaves_like 'an HTTP ingestion adapter',
                  adapter_class: IngestionAdapters::WidenAdapter,
                  credentials: { endpoint: 'https://api.widencollective.com', auth_token: 'token' },
                  fetch_response: {
                    'items' => [{
                      'id' => 'widen-1', 'filename' => 'grid.png', 'description' => 'Grid',
                      'file_properties' => { 'file_size' => 512, 'format' => 'png', 'image_width' => 400, 'image_height' => 300 },
                      'metadata' => { 'keywords' => ['layout'] }, 'created_date' => '2026-01-01', 'last_update_date' => '2026-01-02'
                    }]
                  },
                  expected_identifier: 'widen-1',
                  expected_name: 'grid.png',
                  expected_next_cursor: '1',
                  expected_has_more: false,
                  expected_metadata: { 'title' => 'grid.png', 'width' => 400 },
                  download_id: 'widen-1',
                  download_response: { 'embeds' => [{ 'url' => 'https://downloads.example.com/widen-1' }] },
                  expected_download_url: 'https://downloads.example.com/widen-1',
                  expected_connection_path: 'https://api.widencollective.com/v2/assets/search?query=*&pageSize=1'

  describe IngestionAdapters::S3Adapter do
    subject(:adapter) { described_class.new(nil, region: 'eu-central-1', access_key: 'key', secret_key: 'secret', bucket: 'legacy-bucket') }

    let(:client) { instance_double(Aws::S3::Client) }
    let(:tempfile) do
      instance_double(Tempfile, binmode: true, write: true, rewind: true, path: 'spec/fixtures/files/s3.bin', close: true)
    end

    before do
      allow(Aws::S3::Client).to receive(:new).and_return(client)
      allow(Tempfile).to receive(:new).and_return(tempfile)
    end

    it 'builds an AWS client from the adapter credentials' do
      adapter.client

      expect(Aws::S3::Client).to have_received(:new).with(
        region: 'eu-central-1',
        access_key_id: 'key',
        secret_access_key: 'secret'
      )
    end

    it 'lists and normalizes object metadata' do
      contents = [instance_double(Aws::S3::Types::Object, key: 'folder/file.jpg', size: 99)]
      response = instance_double(Aws::S3::Types::ListObjectsV2Output, contents: contents, next_continuation_token: 'next-token', is_truncated: true)
      allow(client).to receive(:list_objects_v2).and_return(response)

      result = adapter.fetch_next_chunk('cursor', 10)

      expect(result).to eq(
        files: [{ identifier: 'folder/file.jpg', size: 99, original_name: 'file.jpg' }],
        next_cursor: 'next-token',
        has_more: true
      )
    end

    it 'downloads chunks into a tempfile and yields them' do
      allow(client).to receive(:get_object) do |_, &block|
        block.call('abc')
        block.call('def')
      end
      seen = []

      path = adapter.download_and_stream('folder/file.jpg') { |chunk| seen << chunk }

      expect(path).to eq('spec/fixtures/files/s3.bin')
      expect(seen).to eq(%w[abc def])
      expect(tempfile).to have_received(:write).with('abc')
      expect(tempfile).to have_received(:write).with('def')
    end
  end

  describe IngestionAdapters::FtpAdapter do
    subject(:adapter) { described_class.new(nil, host: 'ftp.example.com', port: 21, username: 'user', password: 'pass', remote_path: '/exports') }

    let(:ftp) { instance_double(Net::FTP) }
    let(:tempfile) do
      instance_double(Tempfile, binmode: true, write: true, rewind: true, path: 'spec/fixtures/files/ftp.bin', close: true)
    end

    before do
      allow(Net::FTP).to receive(:open).and_yield(ftp)
      allow(Tempfile).to receive(:new).and_return(tempfile)
    end

    it 'paginates FTP listings and skips directories' do
      allow(ftp).to receive(:chdir).with('/exports')
      allow(ftp).to receive(:list).with('*').and_return([
        '-rw-r--r-- 1 user grp 512 Jun 01 12:00 image.jpg',
        'drwxr-xr-x 1 user grp 0 Jun 01 12:00 nested'
      ])

      result = adapter.fetch_next_chunk(nil, 10)

      expect(result[:files]).to eq([
        identifier: '/exports/image.jpg',
        size: 512,
        original_name: 'image.jpg',
        metadata: { 'modified' => 'Jun 01 12:00', 'source' => 'ftp' }
      ])
      expect(result[:has_more]).to be(false)
    end

    it 'downloads file contents through the FTP client' do
      allow(ftp).to receive(:getbinaryfile) do |_, _, _, &block|
        block.call('chunk-1')
        block.call('chunk-2')
      end
      seen = []

      path = adapter.download_and_stream('/exports/image.jpg') { |chunk| seen << chunk }

      expect(path).to eq('spec/fixtures/files/ftp.bin')
      expect(seen).to eq(['chunk-1', 'chunk-2'])
    end

    it 'tests the connection by listing the remote path' do
      allow(ftp).to receive(:list).and_return([])

      expect(adapter.test_connection).to eq(success: true, message: 'Connected to FTP server ftp.example.com.')
    end
  end

  describe 'header overrides' do
    it 'uses provider-specific headers where required' do
      brandfolder = IngestionAdapters::BrandfolderAdapter.new(nil, auth_token: 'api-key', endpoint: 'https://brandfolder.example.com', brandfolder_key: 'key')
      cloudinary = IngestionAdapters::CloudinaryAdapter.new(nil, cloud_name: 'demo', access_key: 'api', secret_key: 'secret')
      widen = IngestionAdapters::WidenAdapter.new(nil, endpoint: 'https://widen.example.com', auth_token: 'token')
      nuxeo = IngestionAdapters::NuxeoAdapter.new(nil, endpoint: 'https://nuxeo.example.com', username: 'user', password: 'pass')

      expect(brandfolder.send(:default_headers)['X-API-Key']).to eq('api-key')
      expect(cloudinary.send(:default_headers)['Authorization']).to start_with('Basic ')
      expect(widen.send(:default_headers)).to include('X-Requested-With' => 'XMLHttpRequest')
      expect(nuxeo.send(:default_headers)['Authorization']).to start_with('Basic ')
    end
  end
end
