# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Comments coverage', type: :request do
  let(:author) { create(:user) }
  let(:other_user) { create(:user) }
  let(:asset) { create(:asset, user: author) }
  let!(:version_one) { create(:asset_version, asset: asset, version_number: 1) }
  let!(:version_two) { create(:asset_version, asset: asset, version_number: 2) }
  let(:thread) { asset.comment_threads.create!(created_by: author, origin_version: version_one) }
  let!(:root_comment) { thread.comments.create!(body: 'Root feedback', author: author, asset_version: version_one) }

  before do
    asset.update!(active_version: version_two)
    sign_in author
    allow(EmailOrchestrator).to receive(:trigger)
  end

  def parsed_body
    response.parsed_body
  end

  describe 'POST /api/v1/comment_threads/:comment_thread_id/comments' do
    it 'creates a reply under a root comment' do
      post "/api/v1/comment_threads/#{thread.id}/comments", params: {
        body: 'Replying here',
        parent_comment_id: root_comment.id,
        asset_version_id: version_one.id,
      }, as: :json

      expect(response).to have_http_status(:created)
      reply = Comment.find(parsed_body['id'])
      expect(reply.parent_comment).to eq(root_comment)
      expect(reply.motivation).to eq('replying')
      expect(parsed_body['parent_comment_id']).to eq(root_comment.id)
    end

    it 'rejects single-level threading violations' do
      reply = thread.comments.create!(body: 'First reply', author: author, asset_version: version_one, parent_comment: root_comment)

      post "/api/v1/comment_threads/#{thread.id}/comments", params: {
        body: 'Nested reply',
        parent_comment_id: reply.id,
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(parsed_body['error']).to include('threading is single-level')
    end

    it 'returns 404 when the parent comment id does not exist' do
      post "/api/v1/comment_threads/#{thread.id}/comments", params: {
        body: 'Reply to nowhere',
        parent_comment_id: SecureRandom.uuid,
      }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 when the parent comment belongs to a different thread' do
      other_thread = asset.comment_threads.create!(created_by: author, origin_version: version_one)
      other_comment = other_thread.comments.create!(body: 'Other thread', author: author, asset_version: version_one)

      post "/api/v1/comment_threads/#{thread.id}/comments", params: {
        body: 'Cross-thread reply',
        parent_comment_id: other_comment.id,
      }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'marks an open thread addressed when requested' do
      post "/api/v1/comment_threads/#{thread.id}/comments", params: {
        body: 'Fixed in v2',
        asset_version_id: version_two.id,
        mark_addressed: true,
      }, as: :json

      expect(response).to have_http_status(:created)
      expect(thread.reload.status).to eq('addressed')
      expect(Comment.find(parsed_body['id']).asset_version).to eq(version_two)
    end

    it "defaults the comment to the asset's active version" do
      post "/api/v1/comment_threads/#{thread.id}/comments", params: { body: 'Current version follow-up' }, as: :json

      expect(response).to have_http_status(:created)
      expect(Comment.find(parsed_body['id']).asset_version).to eq(version_two)
    end
  end

  describe 'PATCH /api/v1/comments/:id' do
    it 'edits the body, stamps edited_at, and returns edited true' do
      patch "/api/v1/comments/#{root_comment.id}", params: { body: 'Edited feedback' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(root_comment.reload.body).to eq('Edited feedback')
      expect(root_comment.edited_at).to be_present
      expect(parsed_body['edited']).to be(true)
    end

    it 'allows only the author to edit' do
      sign_in other_user

      patch "/api/v1/comments/#{root_comment.id}", params: { body: 'Hijack' }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(root_comment.reload.body).to eq('Root feedback')
    end
  end

  describe 'DELETE /api/v1/comments/:id' do
    it 'allows only the author to delete' do
      sign_in other_user

      delete "/api/v1/comments/#{root_comment.id}", as: :json

      expect(response).to have_http_status(:forbidden)
      expect(root_comment.reload.deleted_at).to be_nil
    end

    it 'soft-deletes the comment' do
      delete "/api/v1/comments/#{root_comment.id}", as: :json

      expect(response).to have_http_status(:no_content)
      expect(Comment.find(root_comment.id).deleted_at).to be_present
      expect(thread.reload.comments.active).not_to include(root_comment)
    end
  end
end
