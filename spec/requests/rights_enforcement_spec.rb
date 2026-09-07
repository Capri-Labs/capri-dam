require "rails_helper"

# Rights enforcement at the byte-delivery boundary (Phase 10b).
#
# Phase 10a made usage terms and licence expiry trustworthy; this file proves
# they are actually consulted before an asset is handed over. Each example maps
# to one delivery surface, because a policy object that nothing calls is not a
# control.
RSpec.describe "Rights enforcement on delivery", type: :request do
  let(:user) { create(:user) }

  describe "the guest review surface" do
    def mint_for(asset, **opts)
      ReviewLink.mint(target: asset, created_by: user, name: "Client review",
                      require_email: false, **opts)
    end

    it "refuses to preview an internal-only asset to a guest" do
      # The default for any asset is internal_only, so this is the common case:
      # sharing something nobody has cleared for external release.
      #
      # 404 rather than 403 is deliberate: a restricted asset is filtered out of
      # the link's scope entirely (ReviewLink#distributable_assets), so a guest
      # cannot tell "not shared with you" from "shared but restricted".
      asset = create(:asset, user: user, properties: { "content_type" => "image/jpeg" })
      _link, token = mint_for(asset)

      get "/s/reviews/#{token}/assets/#{asset.id}/preview"

      expect(response).to have_http_status(:not_found)
    end

    it "refuses to preview an asset whose licence has lapsed" do
      asset = create(:asset, :license_expired, user: user,
                             properties: { "content_type" => "image/jpeg" })
      _link, token = mint_for(asset)

      get "/s/reviews/#{token}/assets/#{asset.id}/preview"

      expect(response).to have_http_status(:not_found)
    end

    it "refuses to download a restricted asset even when the link allows downloads" do
      # allow_downloads? is a per-link permission and is orthogonal to rights:
      # it can be true on a link pointing at an asset nobody may distribute.
      asset = create(:asset, user: user, properties: { "content_type" => "image/jpeg" })
      _link, token = mint_for(asset, allow_downloads: true)

      get "/s/reviews/#{token}/assets/#{asset.id}/download"

      expect(response).to have_http_status(:not_found)
    end

    it "hides a restricted asset from the guest listing entirely" do
      # Refusing the bytes but still listing the title, dimensions and comment
      # thread of an unreleased asset is most of the disclosure the restriction
      # existed to prevent.
      restricted = create(:asset, user: user, title: "Unannounced product")
      cleared    = create(:asset, :externally_distributable, user: user, title: "Press shot")
      collection = create(:collection, user: user, name: "Launch")
      collection.assets << [ restricted, cleared ]
      _link, token = ReviewLink.mint(target: collection, created_by: user,
                                     name: "Launch review", require_email: false)

      get "/s/reviews/#{token}/assets", headers: { "Accept" => "application/json" }

      titles = response.parsed_body["assets"].map { |a| a["title"] }
      expect(titles).to eq([ "Press shot" ])
      expect(response.body).not_to include("Unannounced product")
    end

    it "does not disclose why the asset was refused" do
      # An unauthenticated visitor does not need to learn that the asset exists
      # but is restricted, or when its licence lapsed.
      asset = create(:asset, user: user, properties: { "content_type" => "image/jpeg" })
      _link, token = mint_for(asset)

      get "/s/reviews/#{token}/assets/#{asset.id}/preview"

      expect(response.body).to be_blank
    end

    it "still refuses an asset outside the link's scope with 404, not 403" do
      # Rights enforcement must not turn "no such asset here" into "you may not
      # have this", which would confirm the asset's existence to a guest.
      asset = create(:asset, :externally_distributable, user: user)
      other = create(:asset, :externally_distributable, user: user)
      _link, token = mint_for(asset)

      get "/s/reviews/#{token}/assets/#{other.id}/preview"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the watermarked export endpoint" do
    before { sign_in user }

    it "refuses an asset whose licence has lapsed" do
      # A watermark makes misuse easier to trace; it does not make an expired
      # licence valid again.
      asset = create(:asset, :license_expired, user: user,
                             properties: { "content_type" => "image/jpeg" })

      get "/api/v1/assets/#{asset.id}/watermarked"

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to match(/licence expired/i)
    end

    it "does not refuse an internal-only asset" do
      # Internal staff taking an internal copy is what internal_only is for.
      # It must fail past the rights gate, on the missing file, not on rights.
      asset = create(:asset, user: user, properties: { "content_type" => "image/jpeg" })

      get "/api/v1/assets/#{asset.id}/watermarked"

      # 500 from MiniMagick on the missing fixture file: it got past the rights
      # gate and reached the actual work. Asserting the specific status keeps
      # this example from going vacuous if authentication ever regresses to 401.
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "AssetUrlHelper#asset_download_url_for" do
    let(:helper) do
      Class.new do
        include AssetUrlHelper
        attr_reader :current_user

        def initialize(current_user) = @current_user = current_user
        # The URL builder itself is not under test here — only the gate in
        # front of it.
        def asset_url_for(_asset, disposition: nil) = "https://cdn.example/file?d=#{disposition}"
      end.new(user)
    end

    it "returns nil rather than minting a URL for a lapsed licence" do
      # In production this URL is a presigned S3 link or a signed CDN path. Once
      # it exists the application can no longer refuse, so issuance is the only
      # enforceable moment.
      asset = create(:asset, :license_expired, user: user)

      expect(helper.asset_download_url_for(asset)).to be_nil
    end

    it "mints a URL for an asset with a current licence" do
      asset = create(:asset, :externally_distributable, user: user)

      expect(helper.asset_download_url_for(asset)).to include("d=download")
    end

    it "refuses to mint an external URL for an internal-only asset" do
      asset = create(:asset, user: user)

      expect(helper.asset_download_url_for(asset, audience: :external)).to be_nil
      expect(helper.asset_download_url_for(asset, audience: :internal)).to be_present
    end
  end
end
