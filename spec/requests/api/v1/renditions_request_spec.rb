require 'rails_helper'

# Manual rendition CRUD. The cases that matter are the ones the table's own
# constraints make awkward: a NOT NULL storage backend that has to be resolved
# before the row can exist, and a stored object that has to go when it does.
RSpec.describe 'Api::V1::Renditions', type: :request do
  let(:user)  { create(:user) }
  let(:asset) { create(:asset, user: user, title: 'Hero') }
  let!(:backend) { create(:storage_backend, name: 'Primary', active: true) }

  let(:adapter) do
    instance_double(StorageAdapters::LocalStorageAdapter,
                    store: 'stored', delete: true, url: 'https://cdn.test/r.jpg')
  end

  def upload(content_type: 'image/jpeg', filename: 'test-image.jpg')
    fixture_file_upload(Rails.root.join('spec/fixtures/images', filename), content_type)
  end

  before do
    sign_in user
    allow_any_instance_of(StorageBackend).to receive(:adapter).and_return(adapter)
  end

  describe 'POST /api/v1/assets/:asset_id/renditions' do
    it 'stores the file and records the rendition' do
      expect do
        post "/api/v1/assets/#{asset.id}/renditions",
             params: { file: upload, kind: 'print_cmyk' }
      end.to change(Rendition, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['kind']).to eq('print_cmyk')
      expect(body['source']).to eq('manual')
      expect(body['storage_backend']).to eq('Primary')
      expect(body['url']).to eq('https://cdn.test/r.jpg')
      expect(adapter).to have_received(:store)
    end

    # The bytes must be written through the same backend record the row names,
    # or the row would point somewhere the object is not.
    it 'records the backend it actually wrote to' do
      post "/api/v1/assets/#{asset.id}/renditions", params: { file: upload, kind: 'print_cmyk' }

      expect(Rendition.last.storage_backend_id).to eq(backend.id)
    end

    it 'accepts a uuid in place of the asset id' do
      post "/api/v1/assets/#{asset.uuid}/renditions", params: { file: upload, kind: 'social_square' }

      expect(response).to have_http_status(:created)
    end

    # Dimensions are a property of the file. A caller that reported them wrongly
    # would make every downstream layout decision wrong with it.
    it 'derives image dimensions rather than trusting the caller' do
      post "/api/v1/assets/#{asset.id}/renditions",
           params: { file: upload, kind: 'print_cmyk', width: '9999', height: '9999' }

      rendition = Rendition.last
      expect(rendition.width).to be_present
      expect(rendition.width).not_to eq(9999)
    end

    it 'stores submitted metadata alongside the source marker' do
      post "/api/v1/assets/#{asset.id}/renditions",
           params: { file: upload, kind: 'print_cmyk', metadata: { 'profile' => 'ISOcoated_v2' }.to_json }

      expect(Rendition.last.metadata).to include('profile' => 'ISOcoated_v2', 'source' => 'manual')
    end

    it 'requires a file' do
      post "/api/v1/assets/#{asset.id}/renditions", params: { kind: 'print_cmyk' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/file is required/i)
    end

    it 'rejects a malformed kind' do
      post "/api/v1/assets/#{asset.id}/renditions", params: { file: upload, kind: 'Print CMYK' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors'].join).to match(/lowercase/)
    end

    # Other code is entitled to assume a "thumbnail" came from the thumbnailer.
    it 'refuses to let a manual upload claim a pipeline-owned kind' do
      Rendition::SYSTEM_KINDS.each do |reserved|
        expect do
          post "/api/v1/assets/#{asset.id}/renditions", params: { file: upload, kind: reserved }
        end.not_to change(Rendition, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['reserved_kinds']).to include(reserved)
      end
    end

    it 'refuses a second rendition of the same kind' do
      post "/api/v1/assets/#{asset.id}/renditions", params: { file: upload, kind: 'print_cmyk' }
      expect(response).to have_http_status(:created)

      expect do
        post "/api/v1/assets/#{asset.id}/renditions", params: { file: upload, kind: 'print_cmyk' }
      end.not_to change(Rendition, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors'].join).to match(/already exists/)
    end

    # A rejected row must not leave bytes behind that nothing points at.
    it 'discards the stored object when the row is rejected' do
      create(:rendition, asset: asset, kind: 'print_cmyk')

      post "/api/v1/assets/#{asset.id}/renditions", params: { file: upload, kind: 'print_cmyk' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(adapter).to have_received(:delete)
    end

    # Storing somewhere we cannot name would produce a row we could never
    # resolve again, so the upload is refused rather than guessed at.
    it 'refuses the upload when no backend is active' do
      StorageBackend.update_all(active: false)

      expect do
        post "/api/v1/assets/#{asset.id}/renditions", params: { file: upload, kind: 'print_cmyk' }
      end.not_to change(Rendition, :count)

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body['error']).to match(/no active storage backend/i)
    end

    it 'rejects an upload over the configured size limit' do
      allow(Setting).to receive(:get).with('max_upload_size_bytes').and_return('10')

      post "/api/v1/assets/#{asset.id}/renditions", params: { file: upload, kind: 'print_cmyk' }

      expect(response).to have_http_status(:payload_too_large)
    end

    it '404s for an unknown asset' do
      post '/api/v1/assets/00000000-0000-0000-0000-000000000000/renditions',
           params: { file: upload, kind: 'print_cmyk' }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/assets/:asset_id/renditions' do
    it 'lists the renditions of one asset only' do
      create(:rendition, asset: asset, kind: 'print_cmyk', metadata: { 'source' => 'manual' })
      create(:rendition, asset: asset, kind: 'social_square')
      create(:rendition, kind: 'print_cmyk')

      get "/api/v1/assets/#{asset.id}/renditions"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['meta']['total']).to eq(2)
      expect(body['renditions'].map { |r| r['kind'] }).to contain_exactly('print_cmyk', 'social_square')
      expect(body['renditions'].map { |r| r['source'] }).to contain_exactly('manual', 'generated')
    end

    # An internal address is not part of the contract; publishing it invites
    # callers to build their own URLs against a layout that may change.
    it 'never exposes the storage key' do
      create(:rendition, asset: asset, kind: 'print_cmyk')

      get "/api/v1/assets/#{asset.id}/renditions"

      expect(response.parsed_body['renditions'].first).not_to have_key('storage_key')
      expect(response.body).not_to include('renditions/')
    end

    # A rendition whose URL cannot currently be resolved is still worth
    # reporting; a broken backend should not turn a listing into a 500.
    it 'reports a rendition whose URL cannot be resolved' do
      create(:rendition, asset: asset, kind: 'print_cmyk')
      allow(adapter).to receive(:url).and_raise(StandardError, 'bucket gone')

      get "/api/v1/assets/#{asset.id}/renditions"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['renditions'].first['url']).to be_nil
    end
  end

  describe 'DELETE /api/v1/assets/:asset_id/renditions/:id' do
    it 'removes the row and the stored object' do
      rendition = create(:rendition, asset: asset, kind: 'print_cmyk', storage_key: 'renditions/x/y.tif')

      expect do
        delete "/api/v1/assets/#{asset.id}/renditions/#{rendition.id}"
      end.to change(Rendition, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['deleted']).to be(true)
      expect(adapter).to have_received(:delete).with('renditions/x/y.tif')
    end

    # Confined to the asset in the path, so a rendition id cannot be used to
    # reach across to another asset's derivative.
    it 'will not delete a rendition belonging to another asset' do
      other = create(:rendition, kind: 'print_cmyk')

      expect do
        delete "/api/v1/assets/#{asset.id}/renditions/#{other.id}"
      end.not_to change(Rendition, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'permissions' do
    let(:folder) { create(:folder) }
    let(:foldered_asset) { create(:asset, user: user, folder: folder) }

    # Adding a rendition changes what the asset is to every downstream
    # consumer, so it is not a read-adjacent act.
    it 'requires modify on the asset to create one' do
      allow_any_instance_of(Api::V1::RenditionsController)
        .to receive(:current_user_admin?).and_return(false)
      allow_any_instance_of(Api::V1::RenditionsController)
        .to receive(:folder_permission?).and_return(false)

      post "/api/v1/assets/#{foldered_asset.id}/renditions", params: { file: upload, kind: 'print_cmyk' }

      expect(response).to have_http_status(:forbidden)
    end

    it 'requires read on the asset to list them' do
      allow_any_instance_of(Api::V1::RenditionsController)
        .to receive(:current_user_admin?).and_return(false)
      allow_any_instance_of(Api::V1::RenditionsController)
        .to receive(:folder_permission?).and_return(false)

      get "/api/v1/assets/#{foldered_asset.id}/renditions"

      expect(response).to have_http_status(:forbidden)
    end
  end
end
