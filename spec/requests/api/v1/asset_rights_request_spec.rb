# frozen_string_literal: true

require "rails_helper"

# API surface for the typed rights fields added in Phase 10a.
#
# The point of these specs is that rights are a *first-class* part of the asset
# representation: readable without digging through the free-form properties
# blob, writable without going through it, and impossible to set to something
# the platform cannot enforce on.
RSpec.describe "Api::V1::Assets rights", type: :request do
  let(:user) { create(:user, :admin) }
  let!(:asset) { create(:asset, user: user) }

  before do
    sign_in user
    allow(AssetProcessorWorker).to receive(:perform_async) if defined?(AssetProcessorWorker)
  end

  def body
    JSON.parse(response.body)
  end

  describe "GET /api/v1/assets/:id" do
    it "exposes a rights block derived from the typed columns" do
      asset.update!(usage_terms: "rights_managed", license_expires_at: 30.days.from_now)

      get "/api/v1/assets/#{asset.uuid}"

      expect(response).to have_http_status(:ok)
      expect(body["rights"]).to include(
        "usage_terms"              => "rights_managed",
        "usage_terms_label"        => "Rights Managed",
        "license_expired"          => false,
        "externally_distributable" => true
      )
      expect(body["rights"]["license_expires_at"]).to be_present
    end

    it "reports an asset whose licence has lapsed as not distributable" do
      asset.update!(usage_terms: "royalty_free", license_expires_at: 1.day.ago)

      get "/api/v1/assets/#{asset.uuid}"

      expect(body["rights"]).to include(
        "license_expired"          => true,
        # Permissive terms do not survive a lapsed licence.
        "externally_distributable" => false
      )
    end

    it "reads rights from the asset even when a version carries a stale copy" do
      # `properties` in the response merges the active version's properties over
      # the asset's, so a stale key on a version could shadow the value actually
      # enforced on. The rights block must not be reachable that way.
      asset.update!(usage_terms: "internal_only")
      version = asset.asset_versions.create!(
        version_number: asset.next_version_number,
        action_type: "metadata_update",
        properties: { "usage_terms" => "public_domain" }
      )
      asset.update!(active_version_id: version.id)

      get "/api/v1/assets/#{asset.uuid}"

      expect(body["properties"]["usage_terms"]).to eq("public_domain")
      expect(body["rights"]["usage_terms"]).to eq("internal_only")
      expect(body["rights"]["externally_distributable"]).to be(false)
    end
  end

  describe "PATCH /api/v1/assets/:id" do
    it "accepts a canonical usage term as a first-class field" do
      patch "/api/v1/assets/#{asset.uuid}", params: { asset: { usage_terms: "editorial_only" } }

      expect(response).to have_http_status(:ok)
      expect(asset.reload.usage_terms).to eq("editorial_only")
      expect(body["rights"]["usage_terms"]).to eq("editorial_only")
    end

    it "canonicalises a legacy free-text term rather than storing it verbatim" do
      patch "/api/v1/assets/#{asset.uuid}", params: { asset: { usage_terms: "Royalty-Free" } }

      expect(response).to have_http_status(:ok)
      expect(asset.reload.usage_terms).to eq("royalty_free")
      expect(asset.properties["usage_terms"]).to eq("royalty_free")
    end

    it "records an ISO 8601 expiry" do
      patch "/api/v1/assets/#{asset.uuid}", params: { asset: { license_expires_at: "2027-03-31" } }

      expect(response).to have_http_status(:ok)
      expect(asset.reload.license_expires_at.to_date).to eq(Date.new(2027, 3, 31))
    end

    it "can clear an expiry, which the metadata blob cannot express" do
      # The free-form metadata payload is compact_blank-ed, so a blank there
      # simply vanishes and the old date survives. A deliberate removal has to
      # be expressible.
      asset.update!(license_expires_at: 30.days.from_now)

      patch "/api/v1/assets/#{asset.uuid}", params: { asset: { license_expires_at: "" } }

      expect(response).to have_http_status(:ok)
      expect(asset.reload.license_expires_at).to be_nil
      expect(asset.properties["license_expires_at"]).to be_nil
    end

    it "rejects an unreadable expiry with 422 instead of guessing a date" do
      patch "/api/v1/assets/#{asset.uuid}", params: { asset: { license_expires_at: "31/12/2026" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["error"]).to match(/ISO 8601/)
      expect(asset.reload.license_expires_at).to be_nil
    end

    it "refuses to leave an unenforceable term on the record" do
      patch "/api/v1/assets/#{asset.uuid}", params: { asset: { usage_terms: "whatever legal says" } }

      expect(response).to have_http_status(:ok)
      # Fail-closed: an unreadable rights statement is not permission, so the
      # asset lands on the restrictive default with the original text kept.
      expect(asset.reload.usage_terms).to eq("internal_only")
      expect(asset.properties["usage_terms_raw"]).to eq("whatever legal says")
      expect(body["rights"]["externally_distributable"]).to be(false)
    end

    it "gives an explicit rights field precedence over the same key in the metadata blob" do
      patch "/api/v1/assets/#{asset.uuid}", params: {
        asset: {
          usage_terms: "internal_only",
          metadata: { usage_terms: "public_domain" },
        },
      }

      expect(response).to have_http_status(:ok)
      expect(asset.reload.usage_terms).to eq("internal_only")
    end

    it "leaves rights untouched when the request does not mention them" do
      asset.update!(usage_terms: "royalty_free", license_expires_at: 30.days.from_now)
      original_expiry = asset.reload.license_expires_at

      patch "/api/v1/assets/#{asset.uuid}", params: { asset: { title: "Renamed" } }

      expect(response).to have_http_status(:ok)
      expect(asset.reload.title).to eq("Renamed")
      expect(asset.usage_terms).to eq("royalty_free")
      expect(asset.license_expires_at.to_i).to eq(original_expiry.to_i)
    end

    it "still accepts rights arriving inside the metadata blob, as importers send them" do
      patch "/api/v1/assets/#{asset.uuid}", params: {
        asset: { metadata: { usage_terms: "Licensed", license_expires_at: "2028-01-15" } },
      }

      expect(response).to have_http_status(:ok)
      expect(asset.reload.usage_terms).to eq("rights_managed")
      expect(asset.license_expires_at.to_date).to eq(Date.new(2028, 1, 15))
    end
  end
end
