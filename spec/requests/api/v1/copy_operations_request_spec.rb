require 'rails_helper'

# Request-spec coverage for the bulk Copy overlay backend
# (Api::V1::CopyOperationsController). Copying is modelled as "duplicate,
# leaving the source untouched", so each scenario exercises the read/create
# permission split, the recursive folder-tree duplication, the shared-blob
# file duplication, and the automatic name-collision suffixing.
RSpec.describe 'Api::V1::CopyOperations coverage', type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    sign_in admin
    allow(FolderContentsCache).to receive(:bust)
  end

  describe 'POST /api/v1/copy_operations' do
    it 'copies multiple folders and assets to a destination folder for an admin, leaving originals untouched' do
      origin      = create(:folder, user: admin, name: 'Origin')
      destination = create(:folder, user: admin, name: 'Destination')
      folder_a    = create(:folder, user: admin, parent: origin, name: 'A')
      folder_b    = create(:folder, user: admin, parent: origin, name: 'B')
      asset       = create(:asset, user: admin, folder: origin, title: 'Copyable')

      post '/api/v1/copy_operations', params: {
        folder_ids: [ folder_a.id, folder_b.id ],
        asset_ids: [ asset.id ],
        destination_folder_id: destination.id,
      }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include('success' => true, 'copied_folders' => 2, 'copied_assets' => 1, 'errors' => [])

      # Originals stay exactly where they were.
      expect(folder_a.reload.parent_id).to eq(origin.id)
      expect(folder_b.reload.parent_id).to eq(origin.id)
      expect(asset.reload.folder_id).to eq(origin.id)

      # New copies exist under the destination.
      expect(Folder.active.where(parent_id: destination.id, name: 'A').count).to eq(1)
      expect(Folder.active.where(parent_id: destination.id, name: 'B').count).to eq(1)
      expect(Asset.active.where(folder_id: destination.id, title: 'Copyable').count).to eq(1)
    end

    it 'copies items to root when destination_folder_id is nil/"root"' do
      origin = create(:folder, user: admin, name: 'Origin')
      folder = create(:folder, user: admin, parent: origin, name: 'A')

      post '/api/v1/copy_operations', params: { folder_ids: [ folder.id ], destination_folder_id: 'root' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(folder.reload.parent_id).to eq(origin.id) # original untouched
      expect(Folder.active.where(parent_id: nil, name: 'A').count).to eq(1)
    end

    it 'recursively copies a folder subtree, including nested subfolders and assets' do
      destination = create(:folder, user: admin, name: 'Destination')
      root_folder = create(:folder, user: admin, name: 'Root')
      child       = create(:folder, user: admin, parent: root_folder, name: 'Child')
      _asset_top  = create(:asset, user: admin, folder: root_folder, title: 'TopAsset')
      _asset_deep = create(:asset, user: admin, folder: child, title: 'DeepAsset')

      post '/api/v1/copy_operations', params: {
        folder_ids: [ root_folder.id ],
        destination_folder_id: destination.id,
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['copied_folders']).to eq(1)

      new_root = Folder.active.find_by(parent_id: destination.id, name: 'Root')
      expect(new_root).to be_present
      expect(Folder.active.where(parent_id: new_root.id, name: 'Child').count).to eq(1)
      new_child = Folder.active.find_by(parent_id: new_root.id, name: 'Child')
      expect(Asset.active.where(folder_id: new_root.id, title: 'TopAsset').count).to eq(1)
      expect(Asset.active.where(folder_id: new_child.id, title: 'DeepAsset').count).to eq(1)

      # Originals remain, untouched.
      expect(root_folder.reload.deleted_at).to be_nil
      expect(child.reload.parent_id).to eq(root_folder.id)
    end

    it 'duplicates the active version file on disk via storage_path (the authoritative file location)' do
      # storage_path — not the legacy ActiveStorage attachment — is how the
      # rest of the app (AssetsController#local, AssetProcessorWorker) locates
      # an asset's file, so Copy must duplicate the physical file at that path
      # rather than relying on ActiveStorage's `.attach`/`.attached?`, which is
      # unreliable for these uuid-keyed models (active_storage_attachments
      # .record_id is a bigint column, so every attachment's record_id is
      # coerced to 0).
      destination  = create(:folder, user: admin, name: 'Destination')
      asset        = create(:asset, user: admin, folder: nil, title: 'WithFile')
      source_path  = "#{asset.uuid}/v1_original.txt"
      StorageAdapters::LocalStorageAdapter::ROOT.call.join(source_path).tap do |full_path|
        FileUtils.mkdir_p(full_path.dirname)
        File.write(full_path, 'hello world')
      end
      version = create(:asset_version, asset: asset, version_number: 1,
                                        properties: { 'storage_path' => source_path })
      asset.update!(active_version_id: version.id)

      post '/api/v1/copy_operations', params: { asset_ids: [ asset.id ], destination_folder_id: destination.id }, as: :json

      expect(response).to have_http_status(:ok)
      new_asset = Asset.active.find_by(folder_id: destination.id, title: 'WithFile')
      expect(new_asset).to be_present
      expect(new_asset.active_version).to be_present
      new_storage_path = new_asset.active_version.properties['storage_path']
      expect(new_storage_path).to be_present
      expect(new_storage_path).not_to eq(source_path)
      copied_full_path = StorageAdapters::LocalStorageAdapter::ROOT.call.join(new_storage_path)
      expect(File.read(copied_full_path)).to eq('hello world')
    ensure
      FileUtils.rm_rf(StorageAdapters::LocalStorageAdapter::ROOT.call.join(asset.uuid)) if defined?(asset)
    end

    it 'appends " (Copy)" when a folder of the same name already exists in the destination, but keeps the ' \
       'original name when copying elsewhere' do
      origin      = create(:folder, user: admin, name: 'Origin')
      destination = create(:folder, user: admin, name: 'Destination')
      folder      = create(:folder, user: admin, parent: origin, name: 'Docs')

      # No collision: name preserved.
      post '/api/v1/copy_operations', params: { folder_ids: [ folder.id ], destination_folder_id: destination.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(Folder.active.where(parent_id: destination.id, name: 'Docs').count).to eq(1)

      # Collision (copying into the same destination again): suffix applied.
      post '/api/v1/copy_operations', params: { folder_ids: [ folder.id ], destination_folder_id: destination.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(Folder.active.where(parent_id: destination.id, name: 'Docs (Copy)').count).to eq(1)

      # Third copy: next suffix.
      post '/api/v1/copy_operations', params: { folder_ids: [ folder.id ], destination_folder_id: destination.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(Folder.active.where(parent_id: destination.id, name: 'Docs (Copy 2)').count).to eq(1)
    end

    it 'appends " (Copy)" to an asset title on collision in the destination folder' do
      destination = create(:folder, user: admin, name: 'Destination')
      asset       = create(:asset, user: admin, folder: nil, title: 'Report')

      post '/api/v1/copy_operations', params: { asset_ids: [ asset.id ], destination_folder_id: destination.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(Asset.active.where(folder_id: destination.id, title: 'Report').count).to eq(1)

      post '/api/v1/copy_operations', params: { asset_ids: [ asset.id ], destination_folder_id: destination.id }, as: :json
      expect(response).to have_http_status(:ok)
      expect(Asset.active.where(folder_id: destination.id, title: 'Report (Copy)').count).to eq(1)
    end

    it 'returns 422 when neither folder_ids nor asset_ids are given' do
      post '/api/v1/copy_operations', params: { destination_folder_id: 'root' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/No folders or assets/)
    end

    it 'returns 404 when the destination folder does not exist' do
      folder = create(:folder, user: admin, name: 'A')

      post '/api/v1/copy_operations', params: { folder_ids: [ folder.id ], destination_folder_id: 999_999 }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'reports a per-item error and skips a folder copy that would create a cycle' do
      parent = create(:folder, user: admin, name: 'Parent')
      child  = create(:folder, user: admin, parent: parent, name: 'Child')

      post '/api/v1/copy_operations', params: { folder_ids: [ parent.id ], destination_folder_id: child.id }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body['success']).to be false
      expect(body['copied_folders']).to eq(0)
      expect(body['errors'].first).to include('type' => 'folder', 'id' => parent.id)
      expect(body['errors'].first['error']).to match(/itself|subfolder/)
    end

    it 'reports per-item errors for missing folders/assets without failing the whole batch' do
      destination = create(:folder, user: admin, name: 'Destination')
      real_asset  = create(:asset, user: admin, folder: nil, title: 'Real')

      post '/api/v1/copy_operations', params: {
        folder_ids: [ 999_999 ],
        asset_ids: [ real_asset.id ],
        destination_folder_id: destination.id,
      }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['copied_assets']).to eq(1)
      expect(body['errors']).to contain_exactly(a_hash_including('type' => 'folder', 'id' => 999_999))
      expect(real_asset.reload.folder_id).to be_nil # original untouched
    end

    it 'busts the cache for the destination folder touched (source folders are unaffected since nothing moved)' do
      origin_a    = create(:folder, user: admin, name: 'OriginA')
      origin_b    = create(:folder, user: admin, name: 'OriginB')
      destination = create(:folder, user: admin, name: 'Destination')
      folder      = create(:folder, user: admin, parent: origin_a, name: 'A')
      asset       = create(:asset, user: admin, folder: origin_b, title: 'Copyable')

      post '/api/v1/copy_operations', params: {
        folder_ids: [ folder.id ],
        asset_ids: [ asset.id ],
        destination_folder_id: destination.id,
      }, as: :json

      expect(response).to have_http_status(:ok)
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

      it 'denies copying a folder when the user lacks :read on the source' do
        origin      = create(:folder, name: 'Origin')
        destination = create(:folder, name: 'Destination')
        folder      = create(:folder, user: origin.user, parent: origin, name: 'A')
        create(:folder_policy, :full_access, folder: destination, user_group: group)

        post '/api/v1/copy_operations', params: { folder_ids: [ folder.id ], destination_folder_id: destination.id }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        body = response.parsed_body
        expect(body['copied_folders']).to eq(0)
        expect(body['errors'].first['error']).to match(/permission/i)
      end

      it 'denies copying an asset when the user lacks :create on the destination' do
        origin      = create(:folder, name: 'Origin')
        destination = create(:folder, name: 'Destination')
        asset       = create(:asset, user: origin.user, folder: origin, title: 'Copyable')
        create(:folder_policy, folder: origin, user_group: group, read_access: true)
        create(:folder_policy, folder: destination, user_group: group, read_access: true)

        post '/api/v1/copy_operations', params: { asset_ids: [ asset.id ], destination_folder_id: destination.id }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        body = response.parsed_body
        expect(body['copied_assets']).to eq(0)
        expect(Asset.active.where(folder_id: destination.id, title: 'Copyable').count).to eq(0)
      end

      it 'allows the copy when the user has :read on source and :create on destination for both folders and assets' do
        origin      = create(:folder, name: 'Origin')
        destination = create(:folder, name: 'Destination')
        folder      = create(:folder, user: origin.user, parent: origin, name: 'A')
        asset       = create(:asset, user: origin.user, folder: origin, title: 'Copyable')
        create(:folder_policy, folder: origin, user_group: group, read_access: true)
        create(:folder_policy, :full_access, folder: destination, user_group: group)

        post '/api/v1/copy_operations', params: {
          folder_ids: [ folder.id ],
          asset_ids: [ asset.id ],
          destination_folder_id: destination.id,
        }, as: :json

        expect(response).to have_http_status(:ok)
        expect(Folder.active.where(parent_id: destination.id, name: 'A').count).to eq(1)
        expect(Asset.active.where(folder_id: destination.id, title: 'Copyable').count).to eq(1)
      end

      it 'allows copying root-level items (no source folder policy needed) into a destination the user can create in' do
        destination = create(:folder, name: 'Destination')
        asset       = create(:asset, user: user, folder: nil, title: 'RootAsset')
        create(:folder_policy, :full_access, folder: destination, user_group: group)

        post '/api/v1/copy_operations', params: { asset_ids: [ asset.id ], destination_folder_id: destination.id }, as: :json

        expect(response).to have_http_status(:ok)
        expect(asset.reload.folder_id).to be_nil # original untouched
        expect(Asset.active.where(folder_id: destination.id, title: 'RootAsset').count).to eq(1)
      end
    end
  end

  it 'returns 401 for unauthenticated requests' do
    sign_out admin

    post '/api/v1/copy_operations', params: { folder_ids: [ 1 ] }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
