require 'rails_helper'

RSpec.describe 'Api::V1::MetadataImports', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /api/v1/metadata_imports' do
    it 'returns the current user\'s non-expired imports' do
      mine    = create(:metadata_import, :completed, user: user)
      expired = create(:metadata_import, :expired, user: user)

      get '/api/v1/metadata_imports'

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body).map { |i| i['id'] }
      expect(ids).to include(mine.id)
      expect(ids).not_to include(expired.id)
    end
  end

  describe 'GET /api/v1/metadata_imports/template' do
    it 'streams the fixed-column starter CSV' do
      get '/api/v1/metadata_imports/template'

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('text/csv')
      header = response.body.lines.first
      expect(header).to include('asset_path', 'copyright', 'tags')
    end
  end

  describe 'POST /api/v1/metadata_imports' do
    let(:upload) do
      fixture_file_upload('metadata_import_sample.csv', 'text/csv')
    end

    it 'creates an import from an uploaded CSV and enqueues the worker' do
      expect {
        post '/api/v1/metadata_imports', params: {
          metadata_import: {
            source_file: upload,
            batch_size: 50,
            field_separator: ',',
            multi_value_delimiter: '|',
            asset_path_column: 'asset_path'
          }
        }
      }.to change(MetadataImportWorker.jobs, :size).by(1)

      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body['status']).to eq('pending')
      expect(body['name']).to eq('metadata_import_sample.csv')
    end

    it 'rejects a request without a file' do
      post '/api/v1/metadata_imports', params: { metadata_import: { batch_size: 50 } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'DELETE /api/v1/metadata_imports/:id' do
    it 'destroys the import' do
      import = create(:metadata_import, user: user)
      delete "/api/v1/metadata_imports/#{import.id}"
      expect(response).to have_http_status(:ok)
      expect(MetadataImport.find_by(id: import.id)).to be_nil
    end
  end
end

