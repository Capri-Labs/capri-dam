# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::CommentThreads coverage', type: :request do
  let(:owner) { create(:user) }
  let(:folder_owner) { create(:user) }
  let(:folder) { create(:folder, user: folder_owner) }
  let(:asset) { create(:asset, user: folder_owner, folder: folder) }
  let!(:version_one) { create(:asset_version, asset: asset, version_number: 1) }
  let!(:version_two) { create(:asset_version, asset: asset, version_number: 2) }

  before do
    asset.update!(active_version: version_two)
    grant_folder_access(owner, folder, :full_access)
    sign_in owner
    allow(EmailOrchestrator).to receive(:trigger)
  end

  def grant_folder_access(user, target_folder, trait)
    group = create(:user_group)
    user.user_groups << group
    create(:folder_policy, trait, folder: target_folder, user_group: group)
  end

  def create_thread(created_by: owner, status: 'open', visibility: 'internal', version: version_one, body: 'Feedback')
    thread = asset.comment_threads.create!(created_by: created_by, origin_version: version, status: status, visibility: visibility)
    thread.comments.create!(body: body, author: created_by, asset_version: version)
    thread
  end

  def parsed_body
    response.parsed_body
  end

  describe 'POST /api/v1/assets/:asset_id/comments' do
    it 'creates a thread and first comment with normalized annotation columns' do
      payload = {
        body: 'The logo is clipped',
        asset_version_id: version_one.id,
        motivation: 'editing',
        annotations: [ {
          media_type: 'image',
          shape: 'rect',
          bbox: { x: 0.1, y: 0.2, w: 0.3, h: 0.4 },
          source: { width: 4000, height: 3000 },
          style: { stroke_color: '#000000' },
          label: 'Logo',
        } ],
      }

      expect {
        post "/api/v1/assets/#{asset.id}/comments", params: payload, as: :json
      }.to change(CommentThread, :count).by(1)
        .and change(Comment, :count).by(1)
        .and change(AnnotationTarget, :count).by(1)

      expect(response).to have_http_status(:created)
      comment = Comment.last
      annotation = comment.annotation_targets.last
      expect(comment.asset_version).to eq(version_one)
      expect(annotation).to have_attributes(
        bbox_x: 0.1,
        bbox_y: 0.2,
        bbox_w: 0.3,
        bbox_h: 0.4,
        source_width: 4000,
        source_height: 3000,
        label: 'Logo'
      )
      response_annotation = parsed_body.dig('comments', 0, 'annotations', 0)
      expect(response_annotation['thread_id']).to eq(comment.comment_thread_id)
      expect(response_annotation['bbox']).to eq('x' => 0.1, 'y' => 0.2, 'w' => 0.3, 'h' => 0.4)
    end

    it "defaults the first comment to the asset's active version" do
      post "/api/v1/assets/#{asset.id}/comments", params: { body: 'Discuss current file' }, as: :json

      expect(response).to have_http_status(:created)
      expect(Comment.last.asset_version).to eq(version_two)
      expect(parsed_body.dig('origin_version', 'id')).to eq(version_two.id)
    end

    it 'allows a user with only read access to create a comment thread' do
      reviewer = create(:user)
      grant_folder_access(reviewer, folder, :read_only)
      sign_in reviewer

      post "/api/v1/assets/#{asset.id}/comments", params: { body: 'Reviewer-only feedback' }, as: :json

      expect(response).to have_http_status(:created)
      expect(Comment.last.author).to eq(reviewer)
    end

    it 'returns 422 when body is missing' do
      post "/api/v1/assets/#{asset.id}/comments", params: {}, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(parsed_body['error']).to include('param is missing')
    end
  end

  describe 'GET /api/v1/assets/:asset_id/comments' do
    it 'filters by version, status, unresolved, and annotated state' do
      version_one_thread = create_thread(version: version_one, status: 'open', body: 'v1')
      addressed_thread = create_thread(version: version_two, status: 'addressed', body: 'v2')
      resolved_thread = create_thread(version: version_two, status: 'resolved', body: 'done')
      annotated_thread = create_thread(version: version_two, status: 'open', body: 'annotated')
      annotated_thread.comments.first.annotation_targets.create!(shape: 'rect', bbox_x: 0.1, bbox_y: 0.1, bbox_w: 0.2, bbox_h: 0.2)

      get "/api/v1/assets/#{asset.id}/comments", params: { version_id: version_one.id }
      expect(parsed_body['threads'].pluck('id')).to contain_exactly(version_one_thread.id)

      get "/api/v1/assets/#{asset.id}/comments", params: { status: 'addressed' }
      expect(parsed_body['threads'].pluck('id')).to contain_exactly(addressed_thread.id)

      get "/api/v1/assets/#{asset.id}/comments", params: { unresolved: true }
      expect(parsed_body['threads'].pluck('id')).to contain_exactly(version_one_thread.id, addressed_thread.id, annotated_thread.id)

      get "/api/v1/assets/#{asset.id}/comments", params: { annotated: true }
      expect(parsed_body['threads'].pluck('id')).to contain_exactly(annotated_thread.id)
      expect(parsed_body['threads'].pluck('id')).not_to include(resolved_thread.id)
    end

    it 'reports the unresolved count for all active threads on the asset' do
      create_thread(status: 'open')
      create_thread(status: 'addressed')
      create_thread(status: 'verified')
      create_thread(status: 'resolved')

      get "/api/v1/assets/#{asset.id}/comments"

      expect(response).to have_http_status(:ok)
      expect(parsed_body.dig('meta', 'unresolved')).to eq(2)
    end

    it 'excludes soft-deleted threads' do
      thread = create_thread
      thread.soft_delete

      get "/api/v1/assets/#{asset.id}/comments"

      expect(response).to have_http_status(:ok)
      expect(parsed_body['threads'].pluck('id')).not_to include(thread.id)
    end
  end

  describe 'PATCH /api/v1/comment_threads/:id/resolve' do
    it 'sets verified resolution metadata' do
      thread = create_thread

      patch "/api/v1/comment_threads/#{thread.id}/resolve", params: { status: 'verified' }, as: :json

      expect(response).to have_http_status(:ok)
      thread.reload
      expect(thread.status).to eq('verified')
      expect(thread.resolved_at).to be_present
      expect(thread.resolved_by).to eq(owner)
    end

    it 'rejects an invalid status' do
      thread = create_thread

      patch "/api/v1/comment_threads/#{thread.id}/resolve", params: { status: 'addressed' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(parsed_body['error']).to eq("status must be 'resolved' or 'verified'")
    end
  end

  describe 'PATCH /api/v1/comment_threads/:id/reopen' do
    it 'clears resolution metadata' do
      thread = create_thread(status: 'verified')
      thread.update!(resolved_at: Time.current, resolved_by: owner)

      patch "/api/v1/comment_threads/#{thread.id}/reopen", as: :json

      expect(response).to have_http_status(:ok)
      expect(thread.reload).to have_attributes(status: 'open', resolved_at: nil, resolved_by_id: nil)
    end
  end

  describe 'management authorization' do
    it "denies non-owners without modify access from resolving and deleting someone else's thread" do
      creator = create(:user)
      manager = create(:user)
      grant_folder_access(creator, folder, :read_only)
      grant_folder_access(manager, folder, :read_only)
      thread = create_thread(created_by: creator)
      sign_in manager

      patch "/api/v1/comment_threads/#{thread.id}/resolve", params: { status: 'resolved' }, as: :json
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/comment_threads/#{thread.id}", as: :json
      expect(response).to have_http_status(:forbidden)
      expect(thread.reload.deleted_at).to be_nil
    end

    it 'allows the thread owner to manage their own thread with read access' do
      creator = create(:user)
      grant_folder_access(creator, folder, :read_only)
      thread = create_thread(created_by: creator)
      sign_in creator

      patch "/api/v1/comment_threads/#{thread.id}/resolve", params: { status: 'resolved' }, as: :json
      expect(response).to have_http_status(:ok)

      delete "/api/v1/comment_threads/#{thread.id}", as: :json
      expect(response).to have_http_status(:no_content)
      expect(thread.reload.deleted_at).to be_present
    end
  end

  describe 'DELETE /api/v1/comment_threads/:id' do
    it 'soft-deletes the thread while keeping the row' do
      thread = create_thread

      delete "/api/v1/comment_threads/#{thread.id}", as: :json

      expect(response).to have_http_status(:no_content)
      expect(CommentThread.find(thread.id).deleted_at).to be_present
      get "/api/v1/assets/#{asset.id}/comments"
      expect(parsed_body['threads'].pluck('id')).not_to include(thread.id)
    end
  end
end
