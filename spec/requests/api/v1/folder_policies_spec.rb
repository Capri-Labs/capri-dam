# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe 'Folder Policies API', type: :request do
  let(:admin)   { FactoryBot.create(:user, admin: true) }
  let(:member)  { FactoryBot.create(:user, admin: false) }
  let(:folder)  { FactoryBot.create(:folder, user: admin) }
  let(:group)   { FactoryBot.create(:user_group, name: 'Editors') }

  # ── GET /api/v1/folders/:id/policies ────────────────────────────────────────
  describe 'GET /api/v1/folders/:id/policies' do
    context 'when unauthenticated' do
      it 'returns 401 or redirect' do
        get "/api/v1/folders/#{folder.id}/policies", as: :json
        expect(response.status).to be_in([ 401, 302 ])
      end
    end

    context 'when authenticated' do
      before { sign_in admin }

      it 'returns explicit and inherited policy arrays' do
        get "/api/v1/folders/#{folder.id}/policies", as: :json
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body).to have_key('explicit_policies')
        expect(body).to have_key('inherited_policies')
        expect(body['explicit_policies']).to be_an(Array)
        expect(body['inherited_policies']).to be_an(Array)
      end

      it 'returns the explicit policy when one exists' do
        FolderPolicy.create!(
          folder_id: folder.id, user_group_id: group.id,
          read_access: true, modify_access: false,
          create_access: false, delete_access: false,
          replicate_access: false, manage_access: false,
          explicit_deny: false
        )
        get "/api/v1/folders/#{folder.id}/policies", as: :json
        body = response.parsed_body
        expect(body['explicit_policies'].size).to eq(1)
        policy = body['explicit_policies'].first
        expect(policy['group_id']).to   eq(group.id)
        expect(policy['group_name']).to eq('Editors')
        expect(policy['read_access']).to be(true)
        expect(policy['modify_access']).to be(false)
      end

      it 'surfaces inherited policies from the parent folder' do
        parent = FactoryBot.create(:folder, user: admin)
        child  = FactoryBot.create(:folder, user: admin, parent_id: parent.id)
        FolderPolicy.create!(
          folder_id: parent.id, user_group_id: group.id,
          read_access: true, modify_access: false,
          create_access: false, delete_access: false,
          replicate_access: false, manage_access: false,
          explicit_deny: false
        )

        get "/api/v1/folders/#{child.id}/policies", as: :json
        body = response.parsed_body
        expect(body['inherited_policies'].size).to be >= 1
        inherited = body['inherited_policies'].first
        expect(inherited['group_id']).to eq(group.id)
        expect(inherited['source_folder_name']).to eq(parent.name)
      end

      it 'returns 404 for a non-existent folder' do
        get '/api/v1/folders/non-existent-id/policies', as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ── POST /api/v1/folders/:id/policies ───────────────────────────────────────
  describe 'POST /api/v1/folders/:id/policies' do
    let(:payload) do
      { group_id: group.id, read_access: true, modify_access: true,
        create_access: false, delete_access: false,
        replicate_access: false, manage_access: false, explicit_deny: false }
    end

    context 'when unauthenticated' do
      it 'returns 401 or redirect' do
        post "/api/v1/folders/#{folder.id}/policies", params: payload, as: :json
        expect(response.status).to be_in([ 401, 302 ])
      end
    end

    context 'when authenticated as admin' do
      before { sign_in admin }

      it 'creates a new policy and returns it' do
        expect {
          post "/api/v1/folders/#{folder.id}/policies", params: payload, as: :json
        }.to change(FolderPolicy, :count).by(1)

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['success']).to be(true)
        expect(body.dig('policy', 'read_access')).to   be(true)
        expect(body.dig('policy', 'modify_access')).to be(true)
      end

      it 'updates an existing policy (upsert semantics)' do
        FolderPolicy.create!(
          folder_id: folder.id, user_group_id: group.id,
          read_access: false, modify_access: false, create_access: false,
          delete_access: false, replicate_access: false, manage_access: false,
          explicit_deny: false
        )

        expect {
          post "/api/v1/folders/#{folder.id}/policies",
               params: payload.merge(read_access: true), as: :json
        }.not_to change(FolderPolicy, :count)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('policy', 'read_access')).to be(true)
      end

      it 'enqueues PropagateAccessPolicyJob when cascade=true' do
        expect(PropagateAccessPolicyJob).to receive(:perform_later).once
        post "/api/v1/folders/#{folder.id}/policies",
             params: payload.merge(cascade: true), as: :json
        expect(response).to have_http_status(:ok)
      end

      it 'does NOT enqueue job when cascade=false' do
        expect(PropagateAccessPolicyJob).not_to receive(:perform_later)
        post "/api/v1/folders/#{folder.id}/policies",
             params: payload.merge(cascade: false), as: :json
        expect(response).to have_http_status(:ok)
      end

      it 'returns 404 when group_id is unknown' do
        post "/api/v1/folders/#{folder.id}/policies",
             params: { group_id: 999_999 }, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when authenticated as a regular user without manage_access' do
      before { sign_in member }

      it 'returns 403 Forbidden' do
        post "/api/v1/folders/#{folder.id}/policies", params: payload, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ── DELETE /api/v1/folders/:id/policies/:group_id ───────────────────────────
  describe 'DELETE /api/v1/folders/:id/policies/:group_id' do
    before do
      FolderPolicy.create!(
        folder_id: folder.id, user_group_id: group.id,
        read_access: true, modify_access: false, create_access: false,
        delete_access: false, replicate_access: false, manage_access: false,
        explicit_deny: false
      )
    end

    context 'when authenticated as admin' do
      before { sign_in admin }

      it 'removes the policy' do
        expect {
          delete "/api/v1/folders/#{folder.id}/policies/#{group.id}", as: :json
        }.to change(FolderPolicy, :count).by(-1)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['success']).to be(true)
      end

      it 'enqueues PropagateAccessPolicyJob when cascade=true' do
        expect(PropagateAccessPolicyJob).to receive(:perform_later).once
        delete "/api/v1/folders/#{folder.id}/policies/#{group.id}?cascade=true", as: :json
        expect(response).to have_http_status(:ok)
      end

      it 'returns 404 when the policy does not exist' do
        delete "/api/v1/folders/#{folder.id}/policies/999999", as: :json
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when authenticated as a regular user without manage_access' do
      before { sign_in member }

      it 'returns 403 Forbidden' do
        delete "/api/v1/folders/#{folder.id}/policies/#{group.id}", as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end

# ── User Groups search (read-only API endpoint) ────────────────────────────────
RSpec.describe 'User Groups search API', type: :request do
  let(:user) { FactoryBot.create(:user) }

  before do
    FactoryBot.create(:user_group, name: 'Alpha Editors')
    FactoryBot.create(:user_group, name: 'Beta Reviewers')
    FactoryBot.create(:user_group, name: 'Gamma Admins')
  end

  describe 'GET /api/v1/user_groups' do
    context 'when unauthenticated' do
      it 'returns 401 or redirect' do
        get '/api/v1/user_groups', as: :json
        expect(response.status).to be_in([ 401, 302 ])
      end
    end

    context 'when authenticated' do
      before { sign_in user }

      it 'returns all groups when no query given' do
        get '/api/v1/user_groups', as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to be_an(Array)
      end

      it 'filters groups by name fragment (case-insensitive)' do
        get '/api/v1/user_groups?q=editor', as: :json
        expect(response).to have_http_status(:ok)
        names = response.parsed_body.map { |g| g['name'] }
        expect(names).to include('Alpha Editors')
        expect(names).not_to include('Beta Reviewers')
      end

      it 'returns the correct fields' do
        get '/api/v1/user_groups?q=Alpha', as: :json
        group = response.parsed_body.first
        expect(group.keys).to include('id', 'name', 'slug', 'is_system', 'description')
      end

      it 'returns empty array when no match' do
        get '/api/v1/user_groups?q=zzznomatch', as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq([])
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
