require 'rails_helper'

# Request-spec coverage for the bulk Move overlay backend
# (Api::V1::MoveOperationsController). Moving is modelled as "delete from
# source, create in destination", so each scenario exercises that
# permission split plus the cycle-guard and per-item error reporting.
RSpec.describe 'Api::V1::MoveOperations coverage', type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    sign_in admin
    allow(FolderContentsCache).to receive(:bust)
  end

  describe 'POST /api/v1/move_operations' do
    it 'moves multiple folders and assets to a destination folder for an admin' do
      origin      = create(:folder, user: admin, name: 'Origin')
      destination = create(:folder, user: admin, name: 'Destination')
      folder_a    = create(:folder, user: admin, parent: origin, name: 'A')
      folder_b    = create(:folder, user: admin, parent: origin, name: 'B')
      asset       = create(:asset, user: admin, folder: origin, title: 'Movable')

      post '/api/v1/move_operations', params: {
        folder_ids: [ folder_a.id, folder_b.id ],
        asset_ids: [ asset.id ],
        destination_folder_id: destination.id,
      }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include('success' => true, 'moved_folders' => 2, 'moved_assets' => 1, 'errors' => [])
      expect(folder_a.reload.parent_id).to eq(destination.id)
      expect(folder_b.reload.parent_id).to eq(destination.id)
      expect(asset.reload.folder_id).to eq(destination.id)
    end

    it 'moves items to root when destination_folder_id is nil/"root"' do
      origin = create(:folder, user: admin, name: 'Origin')
      folder = create(:folder, user: admin, parent: origin, name: 'A')

      post '/api/v1/move_operations', params: { folder_ids: [ folder.id ], destination_folder_id: 'root' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(folder.reload.parent_id).to be_nil
    end

    it 'returns 422 when neither folder_ids nor asset_ids are given' do
      post '/api/v1/move_operations', params: { destination_folder_id: 'root' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/No folders or assets/)
    end

    it 'returns 404 when the destination folder does not exist' do
      folder = create(:folder, user: admin, name: 'A')

      post '/api/v1/move_operations', params: { folder_ids: [ folder.id ], destination_folder_id: 999_999 }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'reports a per-item error and skips a folder move that would create a cycle' do
      parent = create(:folder, user: admin, name: 'Parent')
      child  = create(:folder, user: admin, parent: parent, name: 'Child')

      post '/api/v1/move_operations', params: { folder_ids: [ parent.id ], destination_folder_id: child.id }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body['success']).to be false
      expect(body['moved_folders']).to eq(0)
      expect(body['errors'].first).to include('type' => 'folder', 'id' => parent.id)
      expect(body['errors'].first['error']).to match(/itself|subfolder/)
      expect(parent.reload.parent_id).to be_nil
    end

    it 'reports per-item errors for missing folders/assets without failing the whole batch' do
      destination = create(:folder, user: admin, name: 'Destination')
      real_asset  = create(:asset, user: admin, folder: nil, title: 'Real')

      post '/api/v1/move_operations', params: {
        folder_ids: [ 999_999 ],
        asset_ids: [ real_asset.id ],
        destination_folder_id: destination.id,
      }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['moved_assets']).to eq(1)
      expect(body['errors']).to contain_exactly(a_hash_including('type' => 'folder', 'id' => 999_999))
      expect(real_asset.reload.folder_id).to eq(destination.id)
    end

    it 'busts the cache for every source and destination folder touched' do
      origin_a    = create(:folder, user: admin, name: 'OriginA')
      origin_b    = create(:folder, user: admin, name: 'OriginB')
      destination = create(:folder, user: admin, name: 'Destination')
      folder      = create(:folder, user: admin, parent: origin_a, name: 'A')
      asset       = create(:asset, user: admin, folder: origin_b, title: 'Movable')

      post '/api/v1/move_operations', params: {
        folder_ids: [ folder.id ],
        asset_ids: [ asset.id ],
        destination_folder_id: destination.id,
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(FolderContentsCache).to have_received(:bust).with(origin_a.id)
      expect(FolderContentsCache).to have_received(:bust).with(origin_b.id)
      expect(FolderContentsCache).to have_received(:bust).with(destination.id)
    end

    context 'with a non-admin user and folder policies' do
      let(:user)  { create(:user) }
      let(:group) { create(:user_group) }

      before do
        sign_out admin
        sign_in user
        user.user_groups << group
      end

      it 'denies moving a folder when the user lacks :delete on the source' do
        origin      = create(:folder, name: 'Origin')
        destination = create(:folder, name: 'Destination')
        folder      = create(:folder, user: origin.user, parent: origin, name: 'A')
        create(:folder_policy, folder: origin, user_group: group, read_access: true, modify_access: true)
        create(:folder_policy, :full_access, folder: destination, user_group: group)

        post '/api/v1/move_operations', params: { folder_ids: [ folder.id ], destination_folder_id: destination.id }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        body = response.parsed_body
        expect(body['moved_folders']).to eq(0)
        expect(body['errors'].first['error']).to match(/permission/i)
        expect(folder.reload.parent_id).to eq(origin.id)
      end

      it 'denies moving an asset when the user lacks :create on the destination' do
        origin      = create(:folder, name: 'Origin')
        destination = create(:folder, name: 'Destination')
        asset       = create(:asset, user: origin.user, folder: origin, title: 'Movable')
        create(:folder_policy, :full_access, folder: origin, user_group: group)
        create(:folder_policy, folder: destination, user_group: group, read_access: true)

        post '/api/v1/move_operations', params: { asset_ids: [ asset.id ], destination_folder_id: destination.id }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        body = response.parsed_body
        expect(body['moved_assets']).to eq(0)
        expect(asset.reload.folder_id).to eq(origin.id)
      end

      it 'allows the move when the user has :delete on source and :create on destination for both folders and assets' do
        origin      = create(:folder, name: 'Origin')
        destination = create(:folder, name: 'Destination')
        folder      = create(:folder, user: origin.user, parent: origin, name: 'A')
        asset       = create(:asset, user: origin.user, folder: origin, title: 'Movable')
        create(:folder_policy, :full_access, folder: origin, user_group: group)
        create(:folder_policy, :full_access, folder: destination, user_group: group)

        post '/api/v1/move_operations', params: {
          folder_ids: [ folder.id ],
          asset_ids: [ asset.id ],
          destination_folder_id: destination.id,
        }, as: :json

        expect(response).to have_http_status(:ok)
        expect(folder.reload.parent_id).to eq(destination.id)
        expect(asset.reload.folder_id).to eq(destination.id)
      end

      it 'allows moving root-level items (no source folder policy needed) into a destination the user can create in' do
        destination = create(:folder, name: 'Destination')
        asset       = create(:asset, user: user, folder: nil, title: 'RootAsset')
        create(:folder_policy, :full_access, folder: destination, user_group: group)

        post '/api/v1/move_operations', params: { asset_ids: [ asset.id ], destination_folder_id: destination.id }, as: :json

        expect(response).to have_http_status(:ok)
        expect(asset.reload.folder_id).to eq(destination.id)
      end
    end
  end

  it 'returns 401 for unauthenticated requests' do
    sign_out admin

    post '/api/v1/move_operations', params: { folder_ids: [ 1 ] }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
