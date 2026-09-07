# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::ReviewLinks coverage', type: :request do
  let(:owner)   { create(:user) }
  let(:admin)   { create(:user, :admin) }
  let(:other)   { create(:user) }
  let(:folder)  { create(:folder, user: owner) }
  # Root-level: folder policies do not apply, so this isolates the review-link
  # logic from the folder permission engine, which has its own specs.
  let(:asset)   { create(:asset, user: owner, title: 'Hero shot') }

  def parsed_body
    response.parsed_body
  end

  describe 'POST /api/v1/review_links' do
    before { sign_in owner }

    it 'mints a link and returns the raw token exactly once' do
      post '/api/v1/review_links', params: { asset_id: asset.id, name: 'Client review' }, as: :json

      expect(response).to have_http_status(:created), response.body
      expect(parsed_body['token']).to be_present
      expect(parsed_body['url']).to include(parsed_body['token'])
      expect(parsed_body['status']).to eq('active')
      expect(parsed_body['target_label']).to eq('Hero shot')

      # The token is not recoverable afterwards.
      get "/api/v1/review_links/#{parsed_body["id"]}"
      expect(parsed_body).not_to have_key('token')
      expect(parsed_body).not_to have_key('token_digest')
    end

    it 'requires a target' do
      post '/api/v1/review_links', params: { name: 'Nothing' }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'rejects an expiry beyond the hard cap' do
      post '/api/v1/review_links',
           params: { asset_id: asset.id, name: 'Forever', expires_at: 2.years.from_now },
           as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'stores a passphrase as a digest, never in the response' do
      post '/api/v1/review_links',
           params: { asset_id: asset.id, name: 'Sensitive', passphrase: 'open sesame' },
           as: :json

      expect(response).to have_http_status(:created), response.body
      expect(parsed_body['passphrase_protected']).to be(true)
      expect(response.body).not_to include('open sesame')

      link = ReviewLink.find(parsed_body['id'])
      expect(link.passphrase_matches?('open sesame')).to be(true)
    end

    it 'refuses to share an asset the caller cannot modify' do
      foreign = create(:asset, user: other, folder: create(:folder, user: other))
      post '/api/v1/review_links', params: { asset_id: foreign.id, name: 'Nope' }, as: :json
      expect(response.status).to be_in([ 403, 404 ])
      expect(ReviewLink.count).to eq(0)
    end
  end

  describe 'GET /api/v1/review_links' do
    it 'shows only the caller’s own links' do
      mine, = ReviewLink.mint(target: asset, created_by: owner, name: 'Mine')
      theirs_asset = create(:asset, user: other, folder: create(:folder, user: other))
      ReviewLink.mint(target: theirs_asset, created_by: other, name: 'Theirs')

      sign_in owner
      get '/api/v1/review_links'

      expect(response).to have_http_status(:ok)
      expect(parsed_body['review_links'].map { |l| l['id'] }).to eq([ mine.id ])
    end

    it 'lets an administrator see every link' do
      ReviewLink.mint(target: asset, created_by: owner, name: 'Mine')

      sign_in admin
      get '/api/v1/review_links'

      expect(parsed_body['review_links'].size).to eq(1)
    end

    it 'filters by status' do
      _live, = ReviewLink.mint(target: asset, created_by: owner, name: 'Live')
      dead, = ReviewLink.mint(target: asset, created_by: owner, name: 'Dead')
      dead.revoke!

      sign_in owner
      get '/api/v1/review_links', params: { status: 'revoked' }
      expect(parsed_body['review_links'].map { |l| l['name'] }).to eq([ 'Dead' ])

      get '/api/v1/review_links', params: { status: 'active' }
      expect(parsed_body['review_links'].map { |l| l['name'] }).to eq([ 'Live' ])
    end
  end

  describe 'GET /api/v1/review_links/:id' do
    it 'reports guest activity and redacts a placeholder address' do
      link, = ReviewLink.mint(target: asset, created_by: owner, name: 'Review')
      ReviewGuest.identify!(review_link: link, email: 'priya@client.com', name: 'Priya')
      ReviewGuest.anonymous!(review_link: link)

      sign_in owner
      get "/api/v1/review_links/#{link.id}"

      expect(response).to have_http_status(:ok)
      guests = parsed_body['guests']
      expect(guests.size).to eq(2)
      named = guests.find { |g| g['display_name'] == 'Priya' }
      expect(named['email']).to eq('priya@client.com')
      anon = guests.find { |g| g['anonymous'] }
      expect(anon['email']).to be_nil
      expect(response.body).not_to include('guests.invalid')
    end

    it "hides another user's link" do
      foreign = create(:asset, user: other, folder: create(:folder, user: other))
      link, = ReviewLink.mint(target: foreign, created_by: other, name: 'Theirs')

      sign_in owner
      get "/api/v1/review_links/#{link.id}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v1/review_links/:id' do
    it 'updates settings but never the target' do
      link, = ReviewLink.mint(target: asset, created_by: owner, name: 'Review')
      elsewhere = create(:asset, user: owner)

      sign_in owner
      patch "/api/v1/review_links/#{link.id}",
            params: { allow_downloads: true, name: 'Renamed', asset_id: elsewhere.id },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(parsed_body['allow_downloads']).to be(true)
      expect(parsed_body['name']).to eq('Renamed')
      expect(link.reload.asset_id).to eq(asset.id)
    end
  end

  describe 'DELETE /api/v1/review_links/:id' do
    it 'revokes without destroying the provenance record' do
      link, token = ReviewLink.mint(target: asset, created_by: owner, name: 'Review')

      sign_in owner
      delete "/api/v1/review_links/#{link.id}"

      expect(response).to have_http_status(:ok)
      expect(parsed_body['status']).to eq('revoked')
      expect(ReviewLink.find(link.id)).to be_present
      expect(ReviewLink.find_by_token(token).usable?).to be(false)
    end
  end
end
