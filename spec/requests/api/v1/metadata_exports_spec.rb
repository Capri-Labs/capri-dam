require 'rails_helper'

RSpec.describe 'Api::V1::MetadataExports', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /api/v1/metadata_exports' do
    it 'returns the current user\'s non-expired exports' do
      mine    = create(:metadata_export, :completed, user: user, name: 'mine')
      expired = create(:metadata_export, :expired, user: user)
      other   = create(:metadata_export, :completed, user: create(:user))

      get '/api/v1/metadata_exports'

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body).map { |e| e['id'] }
      expect(ids).to include(mine.id)
      expect(ids).not_to include(expired.id, other.id)
    end
  end

  describe 'POST /api/v1/metadata_exports' do
    it 'creates an export and enqueues the worker' do
      folder = create(:folder, user: user)

      expect {
        post '/api/v1/metadata_exports', params: {
          metadata_export: {
            name: 'q3_assets', folder_id: folder.id,
            include_subfolders: true, property_mode: 'all'
          },
        }, as: :json
      }.to change(MetadataExportWorker.jobs, :size).by(1)

      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body['name']).to eq('q3_assets')
      expect(body['status']).to eq('pending')
    end
  end

  describe 'GET /api/v1/metadata_exports/properties' do
    it 'returns the union of property keys for the folder' do
      folder = create(:folder, user: user)
      create(:asset, folder: folder, user: user, properties: { 'copyright' => 'A', 'region' => 'EMEA' })

      get '/api/v1/metadata_exports/properties', params: { folder_id: folder.id }

      expect(response).to have_http_status(:ok)
      props = JSON.parse(response.body)['properties']
      expect(props).to include('copyright', 'region')
    end
  end

  describe 'GET /api/v1/metadata_exports/:id/download' do
    it 'returns 404 when the export is not yet completed' do
      export = create(:metadata_export, user: user)
      get "/api/v1/metadata_exports/#{export.id}/download"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/metadata_exports/:id' do
    it 'destroys the export' do
      export = create(:metadata_export, user: user)
      delete "/api/v1/metadata_exports/#{export.id}"
      expect(response).to have_http_status(:ok)
      expect(MetadataExport.find_by(id: export.id)).to be_nil
    end
  end
end
