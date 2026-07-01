require 'rails_helper'

RSpec.describe 'Storage adapter provider variants', type: :service do
  let(:client) { instance_double(Aws::S3::Client, head_bucket: true) }

  before do
    allow(Aws::S3::Client).to receive(:new).and_return(client)
  end

  it 'derives the Wasabi endpoint and success message' do
    adapter = StorageAdapters::WasabiAdapter.new(bucket: 'bucket', region: 'us-east-2')

    expect(adapter.send(:client_options)[:endpoint]).to eq('https://s3.us-east-2.wasabisys.com')
    expect(adapter.send(:force_path_style?)).to be(true)
    expect(adapter.send(:test_connection)).to eq(success: true, message: "Connected to Wasabi bucket 'bucket' in us-east-2")
  end

  it 'derives the Backblaze endpoint and success message' do
    adapter = StorageAdapters::BackblazeAdapter.new(bucket: 'bucket', region: 'eu-central-003')

    expect(adapter.send(:client_options)[:endpoint]).to eq('https://s3.eu-central-003.backblazeb2.com')
    expect(adapter.send(:force_path_style?)).to be(true)
    expect(adapter.send(:test_connection)).to eq(success: true, message: "Connected to Backblaze B2 bucket 'bucket' in eu-central-003")
  end

  it 'builds virtual-hosted Spaces URLs for public buckets' do
    adapter = StorageAdapters::SpacesAdapter.new(bucket: 'space', region: 'fra1', acl: 'public-read')

    expect(adapter.send(:client_options)[:endpoint]).to eq('https://fra1.digitaloceanspaces.com')
    expect(adapter.send(:url, 'folder/file.txt')).to eq('https://space.fra1.digitaloceanspaces.com/folder/file.txt')
  end

  it 'prefers CDN URLs for public Spaces buckets when configured' do
    adapter = StorageAdapters::SpacesAdapter.new(bucket: 'space', region: 'fra1', acl: 'public-read', cdn_base_url: 'https://cdn.example.com')

    expect(adapter.send(:url, 'folder/file.txt')).to eq('https://cdn.example.com/folder/file.txt')
  end

  it 'requires an R2 account id to derive the endpoint' do
    adapter = StorageAdapters::R2Adapter.new(bucket: 'bucket')

    expect { adapter.send(:r2_endpoint) }.to raise_error(StorageAdapters::StorageError, /account_id/)
  end

  it 'derives the R2 endpoint and success message' do
    adapter = StorageAdapters::R2Adapter.new(bucket: 'bucket', account_id: 'acct-123')

    expect(adapter.send(:client_options)[:endpoint]).to eq('https://acct-123.r2.cloudflarestorage.com')
    expect(adapter.send(:force_path_style?)).to be(true)
    expect(adapter.send(:test_connection)).to eq(success: true, message: "Connected to Cloudflare R2 bucket 'bucket'")
  end
end
