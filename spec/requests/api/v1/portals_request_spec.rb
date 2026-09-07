require 'rails_helper'

# Management surface for distribution portals. The security-relevant cases —
# who may mint one, whose portals are visible, and that grants cannot be
# pointed outside the link's own target — are the point of this file.
RSpec.describe 'Api::V1::Portals', type: :request do
  let(:owner)      { create(:user) }
  let(:other_user) { create(:user) }
  let(:admin)      { create(:user, :admin) }
  let(:collection) { create(:collection, user: owner, name: 'Partner drop') }

  let(:cleared)  { create(:asset, :externally_distributable, user: owner, title: 'Cleared') }
  let(:internal) { create(:asset, user: owner, title: 'Internal', usage_terms: 'internal_only') }

  before do
    collection.assets << cleared
    collection.assets << internal
  end

  def auth(user)
    sign_in user
  end

  describe 'POST /api/v1/portals' do
    it 'mints a portal and returns the token exactly once' do
      auth(owner)

      post '/api/v1/portals', params: {
        collection_id: collection.id,
        name: 'Agency drop',
        grants: [ { asset_id: cleared.id, permission: 'download' } ],
      }, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['token']).to be_present
      expect(body['url']).to include('/s/portal/')
      expect(body['kind']).to eq('portal')
      expect(body['granted_count']).to eq(1)
      expect(body['downloadable_count']).to eq(1)

      # The raw token is never recoverable afterwards.
      portal = ReviewLink.find(body['id'])
      expect(portal.attributes).not_to include('token')
      get "/api/v1/portals/#{portal.id}"
      expect(response.parsed_body).not_to have_key('token')
    end

    it 'refuses to share a collection the caller does not own' do
      auth(other_user)

      post '/api/v1/portals', params: { collection_id: collection.id, name: 'Sneaky' }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(ReviewLink.portals.count).to eq(0)
    end

    it 'reports which granted assets rights will not actually release' do
      auth(owner)

      post '/api/v1/portals', params: {
        collection_id: collection.id,
        name: 'Mixed',
        grants: [
          { asset_id: cleared.id,  permission: 'download' },
          { asset_id: internal.id, permission: 'download' },
        ],
      }, as: :json

      body = response.parsed_body
      expect(body['granted_count']).to eq(2)
      # Only one will ever reach the partner. Surfacing the gap here is the
      # difference between finding out now and finding out from the partner.
      expect(body['distributable_count']).to eq(1)

      by_title = body['assets'].index_by { |a| a['title'] }
      expect(by_title['Internal']['granted']).to be(true)
      expect(by_title['Internal']['externally_distributable']).to be(false)
    end

    it 'sanitises hostile branding before storing it' do
      auth(owner)

      post '/api/v1/portals', params: {
        collection_id: collection.id,
        name: 'Branded',
        branding: { accent: 'red; background:url(//evil)', logo_url: 'javascript:alert(1)', headline: 'Hello' },
      }, as: :json

      expect(response).to have_http_status(:created)
      branding = response.parsed_body['branding']
      expect(branding['accent']).to eq(Portal::Branding::DEFAULT_ACCENT)
      expect(branding['logo_url']).to be_nil
      expect(branding['headline']).to eq('Hello')
    end
  end

  describe 'grants' do
    let(:portal) do
      ReviewLink.mint(target: collection, created_by: owner, name: 'Drop', kind: 'portal').first
    end

    it 'replaces the grant set declaratively so an omitted asset is withdrawn' do
      auth(owner)
      PortalGrant.create!(review_link: portal, asset: cleared, permission: 'download')
      PortalGrant.create!(review_link: portal, asset: internal, permission: 'view')

      patch "/api/v1/portals/#{portal.id}", params: {
        grants: [ { asset_id: cleared.id, permission: 'view' } ],
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(portal.reload.portal_grants.count).to eq(1)
      expect(portal.portal_grants.first.permission).to eq('view')
    end

    it 'ignores an asset that is not in the portal target' do
      auth(owner)
      foreign = create(:asset, :externally_distributable, user: owner, title: 'Foreign')

      patch "/api/v1/portals/#{portal.id}", params: {
        grants: [ { asset_id: foreign.id, permission: 'download' } ],
      }, as: :json

      expect(response).to have_http_status(:ok)
      # A portal over one collection must never be pointed at another's assets.
      expect(portal.reload.portal_grants).to be_empty
    end

    it 'falls back to the weakest permission for an unrecognised value' do
      auth(owner)

      patch "/api/v1/portals/#{portal.id}", params: {
        grants: [ { asset_id: cleared.id, permission: 'delete-everything' } ],
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(portal.reload.portal_grants.first.permission).to eq('view')
    end
  end

  describe 'GET /api/v1/portals' do
    it "does not list another user's portals" do
      ReviewLink.mint(target: collection, created_by: owner, name: 'Mine', kind: 'portal')
      auth(other_user)

      get '/api/v1/portals'

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['portals']).to be_empty
    end

    it 'lets an administrator see everything' do
      ReviewLink.mint(target: collection, created_by: owner, name: 'Mine', kind: 'portal')
      auth(admin)

      get '/api/v1/portals'

      expect(response.parsed_body['portals'].size).to eq(1)
    end

    it 'does not mix review links into the portal list' do
      ReviewLink.mint(target: collection, created_by: owner, name: 'A review')
      auth(owner)

      get '/api/v1/portals'

      expect(response.parsed_body['portals']).to be_empty
    end

    it 'does not mix portals into the review link list' do
      ReviewLink.mint(target: collection, created_by: owner, name: 'A portal', kind: 'portal')
      auth(owner)

      get '/api/v1/review_links'

      expect(response.parsed_body['review_links']).to be_empty
    end
  end

  describe 'DELETE /api/v1/portals/:id' do
    it 'revokes rather than deletes, preserving the download record' do
      portal = ReviewLink.mint(target: collection, created_by: owner, name: 'Drop', kind: 'portal').first
      PortalDownload.create!(review_link: portal, asset: cleared)
      auth(owner)

      delete "/api/v1/portals/#{portal.id}"

      expect(response).to have_http_status(:ok)
      expect(portal.reload).to be_revoked
      expect(ReviewLink.exists?(portal.id)).to be(true)
      expect(PortalDownload.where(review_link_id: portal.id).count).to eq(1)
    end
  end

  describe 'GET /api/v1/portals/:id/downloads' do
    it 'reports what left and who took it' do
      portal = ReviewLink.mint(target: collection, created_by: owner, name: 'Drop', kind: 'portal').first
      guest = ReviewGuest.identify!(review_link: portal, email: 'priya@partner.example', name: 'Priya')
      PortalDownload.create!(review_link: portal, asset: cleared, review_guest: guest, ip_address: '203.0.113.5')
      auth(owner)

      get "/api/v1/portals/#{portal.id}/downloads"

      expect(response).to have_http_status(:ok)
      record = response.parsed_body['downloads'].first
      expect(record['asset_title']).to eq('Cleared')
      expect(record['guest']).to eq('Priya')
      expect(record['guest_email']).to eq('priya@partner.example')
      expect(record['ip_address']).to eq('203.0.113.5')
    end

    it "refuses another user's download log" do
      portal = ReviewLink.mint(target: collection, created_by: owner, name: 'Drop', kind: 'portal').first
      auth(other_user)

      get "/api/v1/portals/#{portal.id}/downloads"

      expect(response).to have_http_status(:not_found)
    end
  end
end
