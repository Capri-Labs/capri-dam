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
  describe 'DELETE /api/v1/folders/:id' do
    let!(:folder) { create(:folder, user: user) }

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

  # ── PATCH rename + description ───────────────────────────────────────────────
  describe 'PATCH /api/v1/folders/:id' do
    let!(:folder) { create(:folder, user: user, name: 'Old Name') }

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
  describe 'GET /api/v1/folders/:id with sorting' do
    let!(:parent) { create(:folder, user: user, name: 'Parent') }

    before do
      create(:folder, user: user, parent: parent, name: 'Banana')
      create(:folder, user: user, parent: parent, name: 'Apple')
      create(:folder, user: user, parent: parent, name: 'Cherry')
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
      small = create(:asset, user: user, folder: parent, title: 'Small')
      large = create(:asset, user: user, folder: parent, title: 'Large')
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
end
