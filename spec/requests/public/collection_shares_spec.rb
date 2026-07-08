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
    asset = create(:asset, user: owner, title: "Hero Shot", properties: {
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
    asset = create(:asset, user: owner, properties: {
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
end
