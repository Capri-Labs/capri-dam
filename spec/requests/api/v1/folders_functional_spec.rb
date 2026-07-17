# frozen_string_literal: true

require 'rails_helper'

# Functional (non-rswag) request specs for the Folders API additions:
#   • PATCH  /api/v1/folders/:id            (rename + description)
#   • DELETE /api/v1/folders/:id            (soft delete — the routing-bug fix)
#   • GET    /api/v1/folders/:id            (sorting)
#   • GET    /api/v1/folders/:id/profiles   (info drawer data)
RSpec.describe 'Folders API (functional)', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  # ── DELETE (the bug the user reported) ──────────────────────────────────────
  # Uses an admin user so check_folder_permission!(@folder, :delete) is bypassed
  # (non-admin users need an explicit folder policy grant, even for folders
  # they created themselves — see the permission-enforcement spec below).
  describe 'DELETE /api/v1/folders/:id' do
    let(:admin_user) { create(:user, :admin) }
    let!(:folder) { create(:folder, user: admin_user) }

    before { sign_in admin_user }

    it 'soft-deletes the folder and returns 200' do
      delete "/api/v1/folders/#{folder.id}", as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['success']).to be(true)
      expect(folder.reload.deleted_at).not_to be_nil
    end

    it 'is reachable (route exists — regression guard)' do
      expect {
        delete "/api/v1/folders/#{folder.id}", as: :json
      }.to change { folder.reload.deleted_at }.from(nil)
    end
  end

  # ── DELETE permission enforcement (security regression guard) ───────────────
  # DELETE /api/v1/folders/:id previously had NO folder-permission check at
  # all — any authenticated non-admin user could soft-delete ANY folder in
  # the system regardless of the 7-column ACL. This mirrors the existing
  # check_asset_delete! enforcement on assets and closes that gap.
  describe 'DELETE /api/v1/folders/:id permission enforcement' do
    let(:owner)       { create(:user) }
    let(:other_user)  { create(:user) }
    let!(:folder)     { create(:folder, user: owner) }

    it "forbids a user with no folder policy from deleting someone else's folder" do
      sign_in other_user
      delete "/api/v1/folders/#{folder.id}", as: :json
      expect(response).to have_http_status(:forbidden)
      expect(folder.reload.deleted_at).to be_nil
    end

    it 'allows deletion once the user is granted delete_access via a folder policy' do
      group = create(:user_group)
      other_user.user_groups << group
      create(:folder_policy, folder: folder, user_group: group, delete_access: true)

      sign_in other_user
      delete "/api/v1/folders/#{folder.id}", as: :json
      expect(response).to have_http_status(:ok)
      expect(folder.reload.deleted_at).not_to be_nil
    end
  end

  # ── CREATE (subfolder) permission enforcement (security regression guard) ───
  # POST /api/v1/folders previously had NO folder-permission check on the
  # target parent folder — any authenticated user could create a subfolder
  # inside ANY folder in the system regardless of the 7-column ACL. This
  # mirrors the existing check_folder_permission!(target_folder, :create)
  # enforcement already applied to asset uploads (Api::V1::AssetsController).
  describe 'POST /api/v1/folders permission enforcement' do
    let(:owner)       { create(:user) }
    let(:other_user)  { create(:user) }
    let!(:parent)     { create(:folder, user: owner) }

    it "forbids a user with no folder policy from creating a subfolder in someone else's folder" do
      sign_in other_user
      expect {
        post "/api/v1/folders", params: { folder: { name: "Should Not Exist", parent_id: parent.id } }, as: :json
      }.not_to change(Folder, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it 'allows subfolder creation once the user is granted create_access via a folder policy' do
      group = create(:user_group)
      other_user.user_groups << group
      create(:folder_policy, folder: parent, user_group: group, create_access: true)

      sign_in other_user
      post "/api/v1/folders", params: { folder: { name: "Allowed Child", parent_id: parent.id } }, as: :json
      expect(response).to have_http_status(:created)
    end

    it 'still allows creating a root-level folder with no policy at all (folder: nil is always creatable)' do
      sign_in other_user
      post "/api/v1/folders", params: { folder: { name: "Root Folder", parent_id: "root" } }, as: :json
      expect(response).to have_http_status(:created)
    end
  end

  # ── PATCH rename + description ───────────────────────────────────────────────
  # Uses an admin user so check_folder_permission!(@folder, :modify) is bypassed
  # (non-admin users need an explicit folder policy grant, even for folders
  # they created themselves — see PATCH #update (rename) specs in
  # folders_controller_spec.rb for the permission-enforcement coverage).
  describe 'PATCH /api/v1/folders/:id' do
    let(:admin_user) { create(:user, :admin) }
    let!(:folder) { create(:folder, user: admin_user, name: 'Old Name') }

    before { sign_in admin_user }

    it 'renames the folder and regenerates the slug' do
      patch "/api/v1/folders/#{folder.id}",
            params: { folder: { name: 'Brand New Name' } }, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['name']).to eq('Brand New Name')
      expect(body['slug']).to eq('brand-new-name')
    end

    it 'updates the description' do
      patch "/api/v1/folders/#{folder.id}",
            params: { folder: { description: 'A handy description' } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['description']).to eq('A handy description')
    end

    it 'returns 404 for a missing folder' do
      patch '/api/v1/folders/00000000-0000-0000-0000-000000000000',
            params: { folder: { name: 'x' } }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 when name is blank' do
      patch "/api/v1/folders/#{folder.id}",
            params: { folder: { name: '' } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ── Sorting ──────────────────────────────────────────────────────────────────
  # Sorting tests use an admin user so check_folder_permission! is bypassed
  # (non-admin users need explicit folder policies even for folders they created).
  describe 'GET /api/v1/folders/:id with sorting' do
    let(:admin_user) { create(:user, :admin) }
    let!(:parent) { create(:folder, user: admin_user, name: 'Parent') }

    before do
      sign_in admin_user
      create(:folder, user: admin_user, parent: parent, name: 'Banana')
      create(:folder, user: admin_user, parent: parent, name: 'Apple')
      create(:folder, user: admin_user, parent: parent, name: 'Cherry')
    end

    it 'sorts folders by name ascending by default' do
      get "/api/v1/folders/#{parent.id}", as: :json
      names = JSON.parse(response.body)['folders'].map { |f| f['name'] }
      expect(names).to eq(%w[Apple Banana Cherry])
    end

    it 'sorts folders by name descending' do
      get "/api/v1/folders/#{parent.id}?sort=name&direction=desc", as: :json
      names = JSON.parse(response.body)['folders'].map { |f| f['name'] }
      expect(names).to eq(%w[Cherry Banana Apple])
    end

    it 'echoes the applied sort in the response' do
      get "/api/v1/folders/#{parent.id}?sort=created_at&direction=desc", as: :json
      sort = JSON.parse(response.body)['sort']
      expect(sort).to eq('field' => 'created_at', 'direction' => 'desc')
    end

    it 'falls back to name for an invalid sort field' do
      get "/api/v1/folders/#{parent.id}?sort=not_a_field", as: :json
      expect(JSON.parse(response.body)['sort']['field']).to eq('name')
    end

    it 'sorts assets by size when requested' do
      small = create(:asset, user: admin_user, folder: parent, title: 'Small')
      large = create(:asset, user: admin_user, folder: parent, title: 'Large')
      small.update!(properties: small.properties.merge('size' => 100))
      large.update!(properties: large.properties.merge('size' => 5000))

      get "/api/v1/folders/#{parent.id}?sort=size&direction=desc", as: :json
      titles = JSON.parse(response.body)['assets'].map { |a| a['title'] }
      expect(titles.first).to eq('Large')
      expect(titles.last).to eq('Small')
    end
  end

  # ── Profiles (info drawer) ───────────────────────────────────────────────────
  describe 'GET /api/v1/folders/:id/profiles' do
    let!(:folder) { create(:folder, user: user) }

    it 'returns null sections when nothing is assigned' do
      get "/api/v1/folders/#{folder.id}/profiles", as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['image_profile']).to be_nil
      expect(body['video_profile']).to be_nil
      expect(body['metadata_schema']).to be_nil
      expect(body['policies']).to eq([])
    end

    it 'returns the assigned video profile' do
      profile = create(:video_profile, :with_adaptive_presets, name: 'HD Stream')
      VideoProfileFolderAssignment.create!(video_profile: profile, folder_id: folder.id)

      get "/api/v1/folders/#{folder.id}/profiles", as: :json
      vp = JSON.parse(response.body)['video_profile']
      expect(vp['name']).to eq('HD Stream')
      expect(vp['preset_count']).to eq(3)
    end
  end

  # ── asset_count in folder payload ──────────────────────────────────────────
  describe 'GET /api/v1/folders/:id includes asset_count' do
    let!(:admin_user) { create(:user, :admin) }
    let!(:folder) { create(:folder, user: admin_user, name: 'Parent Folder') }
    let!(:child)  { create(:folder, user: admin_user, parent: folder, name: 'Child Folder') }

    before { sign_in admin_user }

    it 'includes asset_count in each subfolder payload' do
      create(:asset, user: admin_user, folder: child, title: 'Asset 1')
      create(:asset, user: admin_user, folder: child, title: 'Asset 2')

      get "/api/v1/folders/#{folder.id}", as: :json
      expect(response).to have_http_status(:ok)
      folders = JSON.parse(response.body)['folders']
      child_payload = folders.find { |f| f['id'].to_s == child.id.to_s }
      expect(child_payload).not_to be_nil
      expect(child_payload['asset_count']).to eq(2)
    end

    it 'returns asset_count 0 when subfolder has no assets' do
      get "/api/v1/folders/#{folder.id}", as: :json
      expect(response).to have_http_status(:ok)
      folders = JSON.parse(response.body)['folders']
      child_payload = folders.find { |f| f['id'].to_s == child.id.to_s }
      expect(child_payload).not_to be_nil
      expect(child_payload['asset_count']).to eq(0)
    end
  end
end
