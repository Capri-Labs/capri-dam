# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Authorization concern', type: :request do
  let(:admin_user)   { FactoryBot.create(:user, admin: true) }
  let(:regular_user) { FactoryBot.create(:user, admin: false) }

  # ---------------------------------------------------------------------------
  # GET /api/v1/upload_restrictions — any authenticated user may read
  # ---------------------------------------------------------------------------
  describe 'GET /api/v1/upload_restrictions' do
    context 'when unauthenticated' do
      it 'returns 401 Unauthorized' do
        get '/api/v1/upload_restrictions'
        expect(response).to have_http_status(:unauthorized).or have_http_status(:redirect)
      end
    end

    context 'when authenticated as a regular user (session)' do
      it 'returns 200 OK' do
        sign_in regular_user
        get '/api/v1/upload_restrictions'
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when authenticated via PAT (read scope)' do
      it 'returns 200 OK' do
        _, raw = PersonalAccessToken.generate_for(regular_user, name: 'test', scopes: 'read')
        get '/api/v1/upload_restrictions',
            headers: { 'Authorization' => "Bearer #{raw}" }
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # PUT /api/v1/upload_restrictions — admin only, requires write/admin PAT
  # ---------------------------------------------------------------------------
  describe 'PUT /api/v1/upload_restrictions' do
    let(:payload) { { allowed_mime_types: [ 'image/jpeg' ] } }

    context 'when unauthenticated' do
      it 'returns 401 or redirect' do
        put '/api/v1/upload_restrictions', params: payload, as: :json
        expect(response.status).to be_in([ 401, 302 ])
      end
    end

    context 'when authenticated as a regular (non-admin) user' do
      it 'returns 403 Forbidden' do
        sign_in regular_user
        put '/api/v1/upload_restrictions', params: payload, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when authenticated as an admin user (session)' do
      it 'returns 200 OK' do
        sign_in admin_user
        put '/api/v1/upload_restrictions', params: payload, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when authenticated as admin via PAT with read scope only' do
      it 'returns 403 because the PAT lacks admin scope' do
        _, raw = PersonalAccessToken.generate_for(admin_user, name: 'readonly', scopes: 'read')
        put '/api/v1/upload_restrictions',
            params: payload,
            headers: { 'Authorization' => "Bearer #{raw}" },
            as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when authenticated as admin via PAT with admin scope' do
      it 'returns 200 OK' do
        _, raw = PersonalAccessToken.generate_for(admin_user, name: 'adminpat', scopes: 'admin')
        put '/api/v1/upload_restrictions',
            params: payload,
            headers: { 'Authorization' => "Bearer #{raw}" },
            as: :json
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/bin/retention_policy — admin only
  # ---------------------------------------------------------------------------
  describe 'PUT /api/v1/bin/retention_policy' do
    let(:payload) { { retention_days: 30 } }

    context 'when authenticated as a regular user' do
      it 'returns 403 Forbidden' do
        sign_in regular_user
        put '/api/v1/bin/retention_policy', params: payload, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when authenticated as an admin user' do
      it 'returns 200 OK' do
        sign_in admin_user
        put '/api/v1/bin/retention_policy', params: payload, as: :json
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Collections — must require auth (was completely unprotected before)
  # ---------------------------------------------------------------------------
  describe 'GET /api/v1/collections' do
    context 'when unauthenticated' do
      it 'returns 401 or redirect (was previously open)' do
        get '/api/v1/collections', as: :json
        expect(response.status).to be_in([ 401, 302 ])
      end
    end

    context 'when authenticated' do
      it 'returns 200 OK' do
        sign_in regular_user
        get '/api/v1/collections', as: :json
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
