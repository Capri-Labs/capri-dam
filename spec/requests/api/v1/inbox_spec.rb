require 'rails_helper'

RSpec.describe 'Api::V1::Inbox', type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let!(:mention_message) { create(:inbox_message, :mention, :with_sender, recipient: user, read_at: nil, body_text: 'Mention body') }
  let!(:read_message) { create(:inbox_message, recipient: user, read_at: 1.hour.ago, body_text: 'Read body') }
  let!(:other_message) { create(:inbox_message, recipient: other_user) }

  describe 'GET /api/v1/inbox' do
    it 'returns messages for the current user only' do
      sign_in user

      get '/api/v1/inbox', as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body.fetch('messages').map { |message| message.fetch('id') }
      expect(ids).to include(mention_message.id, read_message.id)
      expect(ids).not_to include(other_message.id)
      expect(ids).to all(match(/\A[0-9a-f\-]{36}\z/))
    end

    it 'filters unread messages' do
      sign_in user

      get '/api/v1/inbox', params: { unread_only: true }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('messages').map { |message| message.fetch('id') }).to eq([ mention_message.id ])
    end

    it 'filters by message type' do
      sign_in user

      get '/api/v1/inbox', params: { type: 'mention' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('messages').map { |message| message.fetch('message_type') }).to all(eq('mention'))
    end

    it 'returns 401 without authentication' do
      get '/api/v1/inbox', as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/inbox/:id' do
    it 'marks the message as read and returns the body' do
      sign_in user

      get "/api/v1/inbox/#{mention_message.id}", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('message', 'body_text')).to eq('Mention body')
      expect(mention_message.reload.read_at).to be_present
    end
  end

  describe 'PATCH /api/v1/inbox/:id/mark_read' do
    it 'marks a message read and returns unread_count' do
      sign_in user

      patch "/api/v1/inbox/#{mention_message.id}/mark_read", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['success']).to be(true)
      expect(response.parsed_body['unread_count']).to eq(0)
    end
  end

  describe 'PATCH /api/v1/inbox/mark_all_read' do
    it 'marks all messages as read' do
      sign_in user

      patch '/api/v1/inbox/mark_all_read', as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['unread_count']).to eq(0)
      expect(user.inbox_messages.unread).to be_empty
    end
  end

  describe 'PATCH /api/v1/inbox/:id/archive' do
    it 'archives the message' do
      sign_in user

      patch "/api/v1/inbox/#{mention_message.id}/archive", as: :json

      expect(response).to have_http_status(:ok)
      expect(mention_message.reload.archived_at).to be_present
    end
  end

  describe 'PATCH /api/v1/inbox/:id/star' do
    it 'toggles star state' do
      sign_in user

      patch "/api/v1/inbox/#{mention_message.id}/star", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['starred']).to be(true)
    end
  end

  describe 'DELETE /api/v1/inbox/:id' do
    it 'deletes the message' do
      sign_in user

      expect do
        delete "/api/v1/inbox/#{mention_message.id}", as: :json
      end.to change(InboxMessage, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /api/v1/inbox/unread_count' do
    it 'returns unread count' do
      sign_in user

      get '/api/v1/inbox/unread_count', as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['unread_count']).to eq(1)
    end
  end

  describe 'message isolation' do
    it 'does not let one user access another user message' do
      sign_in user

      get "/api/v1/inbox/#{other_message.id}", as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
