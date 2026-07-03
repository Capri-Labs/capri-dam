require 'rails_helper'

RSpec.describe StorageAdapters::SpacesAdapter, type: :service do
  subject(:adapter) { described_class.new(bucket: 'space', region: region, acl: acl) }

  let(:region) { 'fra1' }
  let(:acl) { 'private' }
  let(:client) { instance_double(Aws::S3::Client, head_bucket: true) }

  before do
    allow(Aws::S3::Client).to receive(:new).and_return(client)
  end

  describe 'configuration defaults' do
    it 'falls back to the Spaces default region when none is configured' do
      default_region_adapter = described_class.new(bucket: 'space')

      expect(default_region_adapter.send(:region)).to eq('nyc3')
      expect(default_region_adapter.send(:client_options)[:endpoint]).to eq('https://nyc3.digitaloceanspaces.com')
    end
  end

  describe '#url' do
    it 'uses presigned URLs for private buckets' do
      allow(adapter).to receive(:presign_url).with('folder/file.txt', expires_in: 86_400).and_return('signed-url')

      expect(adapter.send(:url, 'folder/file.txt')).to eq('signed-url')
    end
  end

  describe '#test_connection' do
    it 'customizes the provider success message' do
      expect(adapter.send(:test_connection)).to eq(success: true, message: "Connected to DigitalOcean Space 'space' in fra1")
    end
  end
end
