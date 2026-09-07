require 'rails_helper'

# The externally reachable surface of the distribution portal.
#
# These are the checks an outsider actually hits, so they exercise real
# requests against real routes rather than calling the model directly.
RSpec.describe 'Distribution portal', type: :request do
  let(:user)       { create(:user) }
  let(:collection) { create(:collection, user: user) }

  let(:downloadable) do
    create(:asset, :externally_distributable, user: user, title: 'Downloadable',
           properties: { 'storage_path' => 'ok.txt', 'content_type' => 'text/plain' })
  end
  let(:view_only) do
    create(:asset, :externally_distributable, user: user, title: 'View only',
           properties: { 'storage_path' => 'view.txt', 'content_type' => 'text/plain' })
  end
  let(:ungranted) do
    create(:asset, :externally_distributable, user: user, title: 'Ungranted',
           properties: { 'storage_path' => 'no.txt', 'content_type' => 'text/plain' })
  end
  let(:internal) do
    create(:asset, user: user, title: 'Internal only', usage_terms: 'internal_only',
           properties: { 'storage_path' => 'secret.txt', 'content_type' => 'text/plain' })
  end

  def mint_portal(**opts)
    ReviewLink.mint(target: collection, created_by: user, name: 'Partner portal',
                    kind: 'portal', **opts)
  end

  before do
    [ downloadable, view_only, ungranted, internal ].each { |a| collection.assets << a }
    # Two arguments: the adapter and the path. Stubbing with the real arity is
    # deliberate — a verified double is what exposed the wrong-arity call that
    # had been silently 404ing every guest image request.
    allow(StorageManager).to receive(:read_file_from_adapter).with(anything, anything).and_return('bytes')
  end

  describe 'asset listing' do
    it 'lists only granted assets, with per-asset download permission' do
      link, token = mint_portal
      PortalGrant.create!(review_link: link, asset: downloadable, permission: 'download')
      PortalGrant.create!(review_link: link, asset: view_only, permission: 'view')

      get "/s/portal/#{token}/assets", headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:ok)
      listed = response.parsed_body['assets']
      expect(listed.map { |a| a['title'] }).to contain_exactly('Downloadable', 'View only')

      by_title = listed.index_by { |a| a['title'] }
      expect(by_title['Downloadable']['downloadable']).to be(true)
      expect(by_title['Downloadable']['download_url']).to be_present
      expect(by_title['View only']['downloadable']).to be(false)
      # No URL at all, rather than a URL that 403s: a link the guest cannot
      # use should not be rendered as a button they can press.
      expect(by_title['View only']['download_url']).to be_nil
    end

    it 'never lists an asset that rights forbid leaving, even when granted' do
      link, token = mint_portal
      PortalGrant.create!(review_link: link, asset: internal, permission: 'download')

      get "/s/portal/#{token}/assets", headers: { 'Accept' => 'application/json' }

      titles = response.parsed_body['assets'].map { |a| a['title'] }
      expect(titles).not_to include('Internal only')
      # The title itself is the disclosure, so it must not appear anywhere.
      expect(response.body).not_to include('Internal only')
    end
  end

  describe 'download' do
    it 'delivers a granted, cleared asset and records the download' do
      link, token = mint_portal
      PortalGrant.create!(review_link: link, asset: downloadable, permission: 'download')

      expect {
        get "/s/portal/#{token}/assets/#{downloadable.id}/download"
      }.to change(PortalDownload, :count).by(1)

      expect(response).to have_http_status(:ok)
      record = PortalDownload.last
      expect(record.asset_id).to eq(downloadable.id)
      expect(record.review_link_id).to eq(link.id)
    end

    it 'refuses a view-only grant and records nothing' do
      link, token = mint_portal
      PortalGrant.create!(review_link: link, asset: view_only, permission: 'view')

      expect {
        get "/s/portal/#{token}/assets/#{view_only.id}/download"
      }.not_to change(PortalDownload, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it 'hides an ungranted asset entirely rather than refusing it' do
      _link, token = mint_portal

      get "/s/portal/#{token}/assets/#{ungranted.id}/download"

      # 404, not 403: a partner must not be able to probe which assets exist
      # in the collection by watching the status code change.
      expect(response).to have_http_status(:not_found)
    end

    it 'hides a rights-restricted asset behind the same 404 as an ungranted one' do
      link, token = mint_portal
      PortalGrant.create!(review_link: link, asset: internal, permission: 'download')

      get "/s/portal/#{token}/assets/#{internal.id}/download"

      expect(response).to have_http_status(:not_found)
    end

    it 'stops delivering the moment the link is revoked' do
      link, token = mint_portal
      PortalGrant.create!(review_link: link, asset: downloadable, permission: 'download')
      link.revoke!

      get "/s/portal/#{token}/assets/#{downloadable.id}/download"

      expect(response).to have_http_status(:gone)
    end

    it 'records the guest identity when the portal asked who they were' do
      link, token = mint_portal(require_email: true)
      PortalGrant.create!(review_link: link, asset: downloadable, permission: 'download')

      post "/s/portal/#{token}/identify",
           params: { email: 'priya@partner.example', name: 'Priya' }, as: :json
      expect(response).to have_http_status(:created)

      get "/s/portal/#{token}/assets/#{downloadable.id}/download"

      expect(PortalDownload.last.review_guest.email).to eq('priya@partner.example')
    end
  end

  describe 'kind separation' do
    it 'refuses a review token on the portal surface' do
      _review, token = ReviewLink.mint(target: collection, created_by: user, name: 'Review')

      get "/s/portal/#{token}/assets", headers: { 'Accept' => 'application/json' }

      # A review link carries no grants, so serving it here would either expose
      # the whole collection or nothing depending on the code path. It is
      # refused outright instead.
      expect(response).to have_http_status(:gone)
    end

    it 'refuses a portal token on the review surface' do
      _link, token = mint_portal

      get "/s/reviews/#{token}/assets", headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:gone)
    end

    it 'refuses to unlock a portal token through the review surface' do
      link, token = mint_portal
      link.passphrase = 'open sesame'
      link.save!

      post "/s/reviews/#{token}/unlock", params: { passphrase: 'open sesame' }, as: :json

      expect(response).to have_http_status(:gone)
    end
  end

  describe 'passphrase' do
    it 'gates the portal and lets a correct passphrase through' do
      link, token = mint_portal
      PortalGrant.create!(review_link: link, asset: downloadable, permission: 'download')
      link.passphrase = 'open sesame'
      link.save!

      get "/s/portal/#{token}/assets", headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)

      post "/s/portal/#{token}/unlock", params: { passphrase: 'nope' }, as: :json
      expect(response).to have_http_status(:unauthorized)

      post "/s/portal/#{token}/unlock", params: { passphrase: 'open sesame' }, as: :json
      expect(response).to have_http_status(:ok)

      get "/s/portal/#{token}/assets", headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'the HTML shell' do
    it 'renders without embedding any asset data' do
      link, token = mint_portal
      PortalGrant.create!(review_link: link, asset: downloadable, permission: 'download')

      get "/s/portal/#{token}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('guest-portal-root')
      # The shell is a mount point; assets arrive over the JSON endpoint so
      # that revocation applies to them too.
      expect(response.body).not_to include('Downloadable')
      expect(response.headers['X-Robots-Tag']).to include('noindex')
    end

    it 'falls back to the default accent when branding is hostile' do
      link, token = mint_portal(branding: { 'accent' => 'red; background:url(//evil)' })
      PortalGrant.create!(review_link: link, asset: downloadable, permission: 'download')

      get "/s/portal/#{token}"

      expect(response.body).not_to include('evil')
      expect(response.body).to include(Portal::Branding::DEFAULT_ACCENT)
    end
  end
end
