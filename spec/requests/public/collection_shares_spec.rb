# frozen_string_literal: true

require "rails_helper"

# Covers the unauthenticated, read-only public share page for a Collection
# (see Public::CollectionSharesController, Collection#generate_share_token).
# No `sign_in` is called anywhere in this spec — the whole point of the
# feature is that it works *without* a session.
RSpec.describe "Public::CollectionShares", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:owner) { create(:user, :admin) }

  it "renders the collection read-only when given a valid, unexpired share token" do
    collection = create(:collection, user: owner, name: "Spring Launch")
    # Cleared for external release. A share page filters out anything that may
    # not leave the organisation (the factory default is internal_only), so
    # this must be distributable for the example to be testing share mechanics
    # rather than the rights filter.
    asset = create(:asset, :externally_distributable, user: owner, title: "Hero Shot", properties: {
      "storage_path" => "collection_shares_coverage/hero.txt",
      "content_type" => "text/plain",
    })
    dam_path = Rails.root.join("storage/dam/collection_shares_coverage/hero.txt")
    FileUtils.mkdir_p(dam_path.dirname)
    File.binwrite(dam_path, "hero body")
    create(:collection_asset, collection: collection, asset: asset)
    token = collection.generate_share_token

    get "/s/collections/#{token}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Spring Launch")
    expect(response.body).to include('data-testid="public-share-asset-count"')
    expect(response.body).to include("share_token=#{token}")
  ensure
    FileUtils.rm_rf(Rails.root.join("storage/dam/collection_shares_coverage"))
  end

  it "renders a 410 Gone invalid page for a garbage token" do
    get "/s/collections/not-a-real-token"

    expect(response).to have_http_status(:gone)
    expect(response.body).to include(I18n.t("public.collection_shares.invalid.title"))
  end

  it "renders a 410 Gone invalid page for a tampered token" do
    collection = create(:collection, user: owner)
    token = collection.generate_share_token

    get "/s/collections/#{token}tampered"

    expect(response).to have_http_status(:gone)
  end

  it "renders a 410 Gone invalid page for an expired token" do
    collection = create(:collection, user: owner)
    token = collection.generate_share_token(expires_in: 1.second)

    travel_to(2.seconds.from_now) { get "/s/collections/#{token}" }

    expect(response).to have_http_status(:gone)
  end

  it "renders a 410 Gone invalid page once the collection has been soft-deleted" do
    collection = create(:collection, user: owner)
    token = collection.generate_share_token
    collection.update!(deleted_at: 1.day.ago)

    get "/s/collections/#{token}"

    expect(response).to have_http_status(:gone)
  end

  it "lets an unauthenticated request load an asset thumbnail via the share_token query param" do
    collection = create(:collection, user: owner)
    asset = create(:asset, :externally_distributable, user: owner, properties: {
      "storage_path" => "collection_shares_coverage/thumb.txt",
      "content_type" => "text/plain",
    })
    dam_path = Rails.root.join("storage/dam/collection_shares_coverage/thumb.txt")
    FileUtils.mkdir_p(dam_path.dirname)
    File.binwrite(dam_path, "thumb body")
    create(:collection_asset, collection: collection, asset: asset)
    token = collection.generate_share_token

    get "/api/v1/assets/local/#{asset.uuid}", params: { share_token: token }

    expect(response).to have_http_status(:ok)
  ensure
    FileUtils.rm_rf(Rails.root.join("storage/dam/collection_shares_coverage"))
  end

  it "still requires authentication for the same asset without a share_token" do
    collection = create(:collection, user: owner)
    asset = create(:asset, user: owner)
    create(:collection_asset, collection: collection, asset: asset)

    get "/api/v1/assets/local/#{asset.uuid}"

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a share_token that is valid but for a collection the asset does not belong to" do
    collection = create(:collection, user: owner)
    other_collection = create(:collection, user: owner)
    asset = create(:asset, user: owner)
    create(:collection_asset, collection: other_collection, asset: asset)
    token = collection.generate_share_token

    get "/api/v1/assets/local/#{asset.uuid}", params: { share_token: token }

    expect(response).to have_http_status(:unauthorized)
  end

  # These two cases were live disclosure holes: the share page listed every
  # asset in the collection and the share_token branch of #serve_local handed
  # over the bytes, neither consulting usage terms or licence expiry. Rights
  # enforcement (Phase 10b) had only ever been wired into review links.
  describe "rights enforcement on the public share surface" do
    let(:collection) { create(:collection, user: owner, name: "Mixed rights") }

    it "omits an internal-only asset from the share page entirely" do
      cleared = create(:asset, :externally_distributable, user: owner, title: "Cleared shot")
      internal = create(:asset, user: owner, title: "Internal shot", usage_terms: "internal_only")
      create(:collection_asset, collection: collection, asset: cleared)
      create(:collection_asset, collection: collection, asset: internal)

      get "/s/collections/#{collection.generate_share_token}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cleared shot")
      # The title alone is the disclosure for an unannounced product shot.
      expect(response.body).not_to include("Internal shot")
    end

    it "omits an asset whose licence has expired" do
      lapsed = create(:asset, :license_expired, user: owner, title: "Lapsed shot")
      create(:collection_asset, collection: collection, asset: lapsed)

      get "/s/collections/#{collection.generate_share_token}"

      expect(response.body).not_to include("Lapsed shot")
    end

    it "refuses the bytes of an internal-only asset requested with a valid share token" do
      internal = create(:asset, user: owner, usage_terms: "internal_only", properties: {
        "storage_path" => "collection_shares_coverage/secret.txt",
        "content_type" => "text/plain",
      })
      dam_path = Rails.root.join("storage/dam/collection_shares_coverage/secret.txt")
      FileUtils.mkdir_p(dam_path.dirname)
      File.binwrite(dam_path, "secret body")
      create(:collection_asset, collection: collection, asset: internal)
      token = collection.generate_share_token

      get "/api/v1/assets/local/#{internal.uuid}", params: { share_token: token }

      # The token is genuine and the asset really is in the collection; it is
      # the rights that refuse. Falls back to normal auth, which an
      # unauthenticated caller cannot satisfy.
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include("secret body")
    ensure
      FileUtils.rm_rf(Rails.root.join("storage/dam/collection_shares_coverage"))
    end
  end
end
