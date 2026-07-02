require 'rails_helper'

RSpec.describe 'Api::V1::DuplicateGroups coverage', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'filters resolved and dismissed groups in real request specs' do
    resolved = create(:duplicate_group, :resolved)
    dismissed = create(:duplicate_group, :dismissed)
    create(:duplicate_group, status: 'pending')

    get '/api/v1/duplicate_groups', params: { status: 'resolved' }, as: :json
    expect(JSON.parse(response.body)['groups'].map { |group| group['id'] }).to eq([ resolved.id ])

    get '/api/v1/duplicate_groups', params: { status: 'dismissed' }, as: :json
    expect(JSON.parse(response.body)['groups'].map { |group| group['id'] }).to eq([ dismissed.id ])
  end

  it 'serializes members with fallbacks and active version metadata' do
    group = create(:duplicate_group, status: 'pending', total_count: 2)
    original = create(:asset, user: user, folder: nil)
    duplicate = create(:asset, user: user)
    version = create(:asset_version, asset: original, properties: { 'content_type' => 'image/png', 'size' => 123 })
    original.update!(active_version: version)
    create(:duplicate_group_asset, duplicate_group: group, asset: original, is_original: true)
    create(:duplicate_group_asset, duplicate_group: group, asset: duplicate, is_original: false)

    get "/api/v1/duplicate_groups/#{group.id}", as: :json

    data = JSON.parse(response.body)['group']
    expect(data['assets'].first).to include('asset_id' => original.id, 'is_original' => true, 'folder_name' => 'Root / Uncategorized', 'content_type' => 'image/png', 'file_size' => 123)
  end

  it 'does not soft-delete the original or missing assets when resolving duplicates' do
    group = create(:duplicate_group, status: 'pending')
    original = create(:asset)
    duplicate = create(:asset)
    create(:duplicate_group_asset, duplicate_group: group, asset: original, is_original: true)
    create(:duplicate_group_asset, duplicate_group: group, asset: duplicate, is_original: false)

    patch "/api/v1/duplicate_groups/#{group.id}/resolve", params: { action_type: 'deleted_duplicates', asset_ids_to_delete: [ original.id, duplicate.id, 'missing' ] }, as: :json

    data = JSON.parse(response.body)
    expect(response).to have_http_status(:ok)
    expect(data['deleted_ids']).to eq([ duplicate.id ])
    expect(original.reload.deleted_at).to be_nil
    expect(duplicate.reload.deleted_at).to be_present
  end

  it 'handles resolve failures and empty bulk resolves' do
    group = create(:duplicate_group, status: 'pending')
    allow_any_instance_of(DuplicateGroup).to receive(:resolve!).and_raise(StandardError, 'cannot resolve')

    patch "/api/v1/duplicate_groups/#{group.id}/resolve", params: { action_type: 'kept_all' }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)['error']).to eq('cannot resolve')

    patch '/api/v1/duplicate_groups/bulk_resolve', params: { group_ids: [] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['resolved_count']).to eq(0)
  end

  it 'returns stats and 401 for unauthenticated access' do
    create(:duplicate_group, status: 'pending')
    create(:duplicate_group, :dismissed)

    get '/api/v1/duplicate_groups/stats', as: :json
    expect(JSON.parse(response.body)).to include('pending' => 1, 'dismissed' => 1, 'total' => 2)

    sign_out user
    get '/api/v1/duplicate_groups/stats', as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
