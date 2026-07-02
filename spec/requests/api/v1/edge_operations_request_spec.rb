require 'rails_helper'

RSpec.describe 'Api::V1::EdgeOperations coverage', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'POST /api/v1/edge_operations/sync' do
    it 'enqueues folder and asset sync workers and reports counts' do
      allow(FolderMetadataSyncWorker).to receive(:perform_async)
      allow(EdgeMetadataSyncWorker).to receive(:perform_async)

      post '/api/v1/edge_operations/sync', params: { folders: %w[f1 f2], assets: %w[a1] }, as: :json

      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)).to include('success' => true, 'message' => 'Metadata sync initiated for 2 folders and 1 assets.')
      expect(FolderMetadataSyncWorker).to have_received(:perform_async).with('f1')
      expect(FolderMetadataSyncWorker).to have_received(:perform_async).with('f2')
      expect(EdgeMetadataSyncWorker).to have_received(:perform_async).with('a1')
    end

    it 'uses empty arrays when params are omitted' do
      allow(FolderMetadataSyncWorker).to receive(:perform_async)
      allow(EdgeMetadataSyncWorker).to receive(:perform_async)

      post '/api/v1/edge_operations/sync', params: {}, as: :json

      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)['message']).to eq('Metadata sync initiated for 0 folders and 0 assets.')
      expect(FolderMetadataSyncWorker).not_to have_received(:perform_async)
      expect(EdgeMetadataSyncWorker).not_to have_received(:perform_async)
    end
  end

  describe 'POST /api/v1/edge_operations/purge' do
    it 'enqueues cache invalidations for folder and asset tags' do
      allow(CdnInvalidationWorker).to receive(:perform_async)

      post '/api/v1/edge_operations/purge', params: { folders: %w[f1], assets: %w[a1 a2] }, as: :json

      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)['message']).to eq('Cache purge initiated for 1 folders and 2 assets.')
      expect(CdnInvalidationWorker).to have_received(:perform_async).with('folder', 'f1')
      expect(CdnInvalidationWorker).to have_received(:perform_async).with('asset', 'a1')
      expect(CdnInvalidationWorker).to have_received(:perform_async).with('asset', 'a2')
    end
  end

  it 'returns 401 for unauthenticated requests' do
    sign_out user

    post '/api/v1/edge_operations/sync', params: {}, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
