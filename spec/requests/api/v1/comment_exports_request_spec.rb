# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::CommentExports coverage', type: :request do
  let(:reviewer) { create(:user) }
  let(:folder_owner) { create(:user) }
  let(:folder) { create(:folder, user: folder_owner) }
  let(:asset) { create(:asset, user: folder_owner, folder: folder) }
  let(:other_folder) { create(:folder, user: folder_owner) }
  let(:other_asset) { create(:asset, user: folder_owner, folder: other_folder) }
  let!(:version_one) { create(:asset_version, asset: asset, version_number: 1) }

  before do
    asset.update!(active_version: version_one)
    grant_folder_access(reviewer, folder, :full_access)
    grant_folder_access(reviewer, other_folder, :full_access)
    sign_in reviewer
    allow(EmailOrchestrator).to receive(:trigger)
  end

  def grant_folder_access(user, target_folder, trait)
    group = create(:user_group)
    user.user_groups << group
    create(:folder_policy, trait, folder: target_folder, user_group: group)
  end

  def create_thread(target: asset, version: version_one, status: 'open', body: 'The logo is clipped')
    thread = target.comment_threads.create!(
      created_by: reviewer, origin_version: version, status: status, visibility: 'internal'
    )
    comment = thread.comments.create!(body: body, author: reviewer, asset_version: version, motivation: 'editing')
    comment.annotation_targets.create!(
      media_type: 'image', shape: 'rect',
      bbox_x: 0.1, bbox_y: 0.2, bbox_w: 0.3, bbox_h: 0.4,
      source_width: 4000, source_height: 3000, label: 'Logo'
    )
    [ thread, comment ]
  end

  def parsed_body
    response.parsed_body
  end

  # Rails does not register a parser for application/ld+json, so
  # +response.parsed_body+ hands back the raw String for the JSON-LD export.
  def parsed_jsonld
    JSON.parse(response.body)
  end

  describe 'GET /api/v1/assets/:asset_id/comments/export' do
    before { create_thread }

    it 'emits a W3C Web Annotation page' do
      get "/api/v1/assets/#{asset.id}/comments/export", params: { export_format: 'jsonld' }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/ld+json')

      body = parsed_jsonld
      expect(body['type']).to eq('AnnotationPage')
      expect(body['@context']).to include('http://www.w3.org/ns/anno.jsonld')
      expect(body['items'].size).to eq(1)

      item = body['items'].first
      expect(item['type']).to eq('Annotation')
      expect(item['motivation']).to eq('editing')
      expect(item.dig('body', 'value')).to eq('The logo is clipped')
    end

    it 'expresses image geometry as a percentage media fragment, never pixels' do
      get "/api/v1/assets/#{asset.id}/comments/export", params: { export_format: 'jsonld' }

      selector = parsed_jsonld.dig('items', 0, 'target', 'selector')
      fragment = Array.wrap(selector).find { |s| s['type'] == 'FragmentSelector' }

      # Percent, so the export is not bound to whichever rendition happened to
      # be on screen when the note was drawn.
      expect(fragment['value']).to eq('xywh=percent:10,20,30,40')
      expect(fragment['value']).not_to include('4000')
    end

    it 'carries the capri extension needed for a lossless round trip' do
      get "/api/v1/assets/#{asset.id}/comments/export", params: { export_format: 'jsonld' }

      item = parsed_jsonld['items'].first
      expect(item.dig('target', 'selector', 'capri:shape')).to eq('rect')
      expect(item['capri:threadId']).to be_present
      expect(parsed_jsonld.dig('@context', 1, 'capri')).to be_present
    end

    it 'renders a PDF contact sheet' do
      get "/api/v1/assets/#{asset.id}/comments/export", params: { export_format: 'pdf' }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/pdf')
      expect(response.body[0, 4]).to eq('%PDF')
      expect(response.headers['Content-Disposition']).to include('attachment')
    end

    it 'rejects an unknown format rather than guessing' do
      get "/api/v1/assets/#{asset.id}/comments/export", params: { export_format: 'docx' }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'denies a user with no access to the folder' do
      sign_in create(:user)

      get "/api/v1/assets/#{asset.id}/comments/export", params: { export_format: 'jsonld' }

      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/assets/:asset_id/comments/import' do
    let(:third_party_document) do
      {
        '@context' => 'http://www.w3.org/ns/anno.jsonld',
        'type' => 'AnnotationPage',
        'items' => [
          {
            'id' => 'https://vendor.example/anno/1',
            'type' => 'Annotation',
            'motivation' => 'commenting',
            'creator' => { 'name' => 'Someone Else', 'id' => 'https://vendor.example/users/9' },
            'body' => { 'type' => 'TextualBody', 'value' => 'Crop is too tight', 'format' => 'text/plain' },
            'target' => {
              'source' => 'https://vendor.example/asset/1',
              'selector' => { 'type' => 'FragmentSelector', 'value' => 'xywh=percent:5,5,20,20' },
            },
          },
          {
            'id' => 'https://vendor.example/anno/2',
            'type' => 'Annotation',
            'motivation' => 'replying',
            'body' => { 'type' => 'TextualBody', 'value' => 'Agreed, will refit.' },
            'target' => 'https://vendor.example/anno/1',
          },
        ],
      }
    end

    # A document asserting the conversation already ended.
    let(:resolved_claim_document) do
      doc = Marshal.load(Marshal.dump(third_party_document))
      doc['items'].first['capri:thread'] = { 'status' => 'resolved' }
      doc
    end

    it 'imports a third-party document, nesting the reply under its parent' do
      expect {
        post "/api/v1/assets/#{asset.id}/comments/import",
             params: { document: third_party_document }, as: :json
      }.to change(CommentThread, :count).by(1)
        .and change(Comment, :count).by(2)

      expect(response).to have_http_status(:created)
      expect(parsed_body['comments_created']).to eq(2)

      thread = asset.comment_threads.order(:created_at).last
      root = thread.comments.where(parent_comment_id: nil).first
      reply = thread.comments.where.not(parent_comment_id: nil).first

      expect(root.body).to eq('Crop is too tight')
      expect(reply.parent_comment_id).to eq(root.id)
    end

    it 'attributes imported comments to the importing user, not the file' do
      post "/api/v1/assets/#{asset.id}/comments/import",
           params: { document: third_party_document }, as: :json

      root = asset.comment_threads.order(:created_at).last.comments.order(:created_at).first

      # Honouring the file's creator would let anyone forge "the Creative
      # Director approved this" by editing JSON in a text editor.
      expect(root.author).to eq(reviewer)
      expect(root.import_source['claimed_creator']).to include('name' => 'Someone Else')
      expect(root.import_source['iri']).to eq('https://vendor.example/anno/1')
    end

    let(:external_claim_document) do
      doc = Marshal.load(Marshal.dump(third_party_document))
      doc['items'].first['capri:thread'] = { 'visibility' => 'external' }
      doc
    end

    it 'forces imported threads to internal visibility' do
      post "/api/v1/assets/#{asset.id}/comments/import",
           params: { document: external_claim_document }, as: :json

      expect(asset.comment_threads.order(:created_at).last.visibility).to eq('internal')
    end

    it 'is idempotent: re-importing the same document creates nothing new' do
      post "/api/v1/assets/#{asset.id}/comments/import",
           params: { document: third_party_document }, as: :json

      expect {
        post "/api/v1/assets/#{asset.id}/comments/import",
             params: { document: third_party_document }, as: :json
      }.to change(Comment, :count).by(0).and change(CommentThread, :count).by(0)

      expect(parsed_body['skipped']).to eq(2)
    end

    it 'round-trips its own export losslessly' do
      thread, = create_thread
      get "/api/v1/assets/#{asset.id}/comments/export", params: { export_format: 'jsonld' }
      document = parsed_jsonld

      post "/api/v1/assets/#{other_asset.id}/comments/import", params: { document: document }, as: :json
      expect(response).to have_http_status(:created)

      imported = other_asset.comment_threads.order(:created_at).last.comments.order(:created_at).first
      original = thread.comments.order(:created_at).first
      target = imported.annotation_targets.first

      expect(imported.body).to eq(original.body)
      expect(imported.motivation).to eq(original.motivation)
      expect(target.shape).to eq('rect')
      expect(target.bbox_x).to be_within(0.0001).of(0.1)
      expect(target.bbox_h).to be_within(0.0001).of(0.4)
    end

    it 'does not attach a reply to a thread on a different asset' do
      _thread, comment = create_thread
      get "/api/v1/assets/#{asset.id}/comments/export", params: { export_format: 'jsonld' }
      document = parsed_jsonld

      post "/api/v1/assets/#{other_asset.id}/comments/import", params: { document: document }, as: :json

      # Parent resolution is asset-scoped: a bare global lookup on the embedded
      # UUID would silently graft this onto the original asset's thread.
      expect(other_asset.comment_threads.count).to eq(1)
      expect(comment.reload.replies.count).to eq(0)
    end

    it 'rejects a document that is not an annotation page' do
      post "/api/v1/assets/#{asset.id}/comments/import",
           params: { document: { 'type' => 'Nonsense' } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'lets a read-only reviewer import, but will not let the file close feedback' do
      viewer = create(:user)
      grant_folder_access(viewer, folder, :read_only)
      sign_in viewer

      # Importing is the bulk form of posting a comment, which is a read-level
      # action throughout the app, so it is allowed. Honouring a claimed
      # "resolved" is a lifecycle decision and is not.
      post "/api/v1/assets/#{asset.id}/comments/import",
           params: { document: resolved_claim_document }, as: :json

      expect(response).to have_http_status(:created)
      expect(asset.comment_threads.order(:created_at).last.status).to eq('open')
    end

    it 'honours a claimed status for a user who could have set it by hand' do
      post "/api/v1/assets/#{asset.id}/comments/import",
           params: { document: resolved_claim_document }, as: :json

      expect(asset.comment_threads.order(:created_at).last.status).to eq('resolved')
    end

    it 'denies a user with no access to the asset at all' do
      sign_in create(:user)

      post "/api/v1/assets/#{asset.id}/comments/import",
           params: { document: third_party_document }, as: :json

      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
    end
  end
end
