require 'rails_helper'

# Request-spec coverage for the bulk Download overlay backend
# (Api::V1::AssetDownloadsController). Download never mutates anything, so
# these specs focus on: read-permission filtering, up-front recursive item
# counting (for the progress bar), the "already queued" signal, listing,
# fetching the finished ZIP, and lifecycle (show/destroy). Worker/ZIP-content
# behaviour itself is covered by spec/workers/asset_download_worker_spec.rb.
RSpec.describe 'Api::V1::AssetDownloads coverage', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'POST /api/v1/asset_downloads' do
    it 'creates a download, counts items recursively (including subfolders), and enqueues the worker' do
      folder = create(:folder, user: user, name: 'Origin')
      child  = create(:folder, user: user, parent: folder, name: 'Child')
      create(:asset, user: user, folder: folder, title: 'Top')
      create(:asset, user: user, folder: child, title: 'Deep')
      lone_asset = create(:asset, user: user, folder: nil, title: 'Lone')

      expect {
        post '/api/v1/asset_downloads', params: {
          folder_ids: [ folder.id ],
          asset_ids: [ lone_asset.id ],
        }, as: :json
      }.to change(AssetDownloadWorker.jobs, :size).by(1)

      expect(response).to have_http_status(:accepted)
      body = response.parsed_body
      expect(body['status']).to eq('pending')
      expect(body['total_items']).to eq(3) # Top + Deep + Lone
      expect(body['queued']).to eq(false)
      expect(body['errors']).to eq([])
    end

    it 'auto-generates a name when none is given' do
      asset = create(:asset, user: user, folder: nil)
      post '/api/v1/asset_downloads', params: { asset_ids: [ asset.id ] }, as: :json
      expect(response.parsed_body['name']).to be_present
    end

    it 'rejects an empty selection' do
      post '/api/v1/asset_downloads', params: {}, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'drops items the user cannot read, reporting a per-item error, but still downloads the rest' do
      group          = create(:user_group)
      user.user_groups << group
      origin         = create(:folder, name: 'Origin')
      other_folder   = create(:folder, user: origin.user, parent: origin, name: 'NotMine')
      readable_asset = create(:asset, user: user, folder: nil, title: 'Mine')

      post '/api/v1/asset_downloads', params: {
        folder_ids: [ other_folder.id ],
        asset_ids: [ readable_asset.id ],
      }, as: :json

      expect(response).to have_http_status(:accepted)
      body = response.parsed_body
      expect(body['total_items']).to eq(1) # only the readable asset counted
      expect(body['errors']).not_to be_empty
      expect(body['errors'].first['type']).to eq('folder')
    end

    it 'returns 422 when every selected item is unreadable' do
      group        = create(:user_group)
      user.user_groups << group
      origin       = create(:folder, name: 'Origin')
      other_folder = create(:folder, user: origin.user, parent: origin, name: 'NotMine')

      post '/api/v1/asset_downloads', params: { folder_ids: [ other_folder.id ] }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'reports queued: true when the user already has another pending/processing download' do
      create(:asset_download, user: user, status: :processing)
      asset = create(:asset, user: user, folder: nil)

      post '/api/v1/asset_downloads', params: { asset_ids: [ asset.id ] }, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body['queued']).to eq(true)
    end

    it 'admins bypass folder permission checks' do
      admin        = create(:user, :admin)
      other_folder = create(:folder, user: create(:user), name: 'SomeoneElses')
      sign_in admin

      post '/api/v1/asset_downloads', params: { folder_ids: [ other_folder.id ] }, as: :json
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body['errors']).to eq([])
    end
  end

  describe 'GET /api/v1/asset_downloads' do
    it "lists only the current user's non-expired downloads" do
      mine    = create(:asset_download, :completed, user: user, name: 'mine')
      expired = create(:asset_download, :expired, user: user)
      other   = create(:asset_download, :completed, user: create(:user))

      get '/api/v1/asset_downloads'

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['downloads'].map { |d| d['id'] }
      expect(ids).to include(mine.id)
      expect(ids).not_to include(expired.id, other.id)
    end
  end

  describe 'GET /api/v1/asset_downloads/:id' do
    it "returns the current progress for polling" do
      download = create(:asset_download, :processing, user: user)
      get "/api/v1/asset_downloads/#{download.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['status']).to eq('processing')
      expect(body).to have_key('progress_percent')
    end

    it "404s for another user's download" do
      other_download = create(:asset_download, user: create(:user))
      get "/api/v1/asset_downloads/#{other_download.id}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/asset_downloads/:id/download' do
    it 'returns 404 when the download is not yet completed' do
      download = create(:asset_download, user: user)
      get "/api/v1/asset_downloads/#{download.id}/download"
      expect(response).to have_http_status(:not_found)
    end

    it 'redirects to the attached ZIP when completed' do
      download = create(:asset_download, :completed, user: user)
      download.zip_file.attach(io: StringIO.new('zip'), filename: 'd.zip', content_type: 'application/zip')

      get "/api/v1/asset_downloads/#{download.id}/download"
      expect(response).to have_http_status(:found)
    end
  end

  describe 'DELETE /api/v1/asset_downloads/:id' do
    it 'destroys the download and purges its ZIP' do
      download = create(:asset_download, :completed, user: user)
      download.zip_file.attach(io: StringIO.new('zip'), filename: 'd.zip', content_type: 'application/zip')

      delete "/api/v1/asset_downloads/#{download.id}"
      expect(response).to have_http_status(:ok)
      expect(AssetDownload.find_by(id: download.id)).to be_nil
    end
  end
end
