# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::C2pa & Provenance authorization", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user)  { create(:user) }

  # ---------------------------------------------------------------------------
  # C2PA Configuration
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/c2pa_configuration" do
    it "returns 401 when unauthenticated" do
      get "/api/v1/c2pa_configuration"
      expect(response).to have_http_status(:unauthorized)
    end

    it "forbids non-admins" do
      sign_in user
      get "/api/v1/c2pa_configuration"
      expect(response).to have_http_status(:forbidden)
    end

    it "returns the config for admins" do
      sign_in admin
      get "/api/v1/c2pa_configuration"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("gateway_c2pa_enabled", "verification_strictness")
    end
  end

  describe "PATCH /api/v1/c2pa_configuration" do
    it "updates the config for admins" do
      sign_in admin
      patch "/api/v1/c2pa_configuration",
            params: { c2pa_configuration: { gateway_c2pa_enabled: true, verification_strictness: "strict" } },
            as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("config", "gateway_c2pa_enabled")).to be(true)
    end

    it "returns 422 on invalid data" do
      sign_in admin
      patch "/api/v1/c2pa_configuration",
            params: { c2pa_configuration: { verification_strictness: "bogus" } },
            as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "forbids non-admins" do
      sign_in user
      patch "/api/v1/c2pa_configuration",
            params: { c2pa_configuration: { gateway_c2pa_enabled: true } },
            as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  # ---------------------------------------------------------------------------
  # Asset Provenance Records — index / stats / show
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/asset_provenance_records" do
    it "returns 401 when unauthenticated" do
      get "/api/v1/asset_provenance_records"
      expect(response).to have_http_status(:unauthorized)
    end

    it "forbids non-admins" do
      sign_in user
      get "/api/v1/asset_provenance_records"
      expect(response).to have_http_status(:forbidden)
    end

    it "returns records for admins" do
      sign_in admin
      create(:asset_provenance_record, :verified)
      get "/api/v1/asset_provenance_records"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["records"].size).to eq(1)
    end

    it "filters by status" do
      sign_in admin
      create(:asset_provenance_record, :verified)
      create(:asset_provenance_record, :missing)
      get "/api/v1/asset_provenance_records?status=verified"
      body = JSON.parse(response.body)
      expect(body["records"].map { |r| r["manifest_status"] }).to all(eq("verified"))
    end
  end

  describe "GET /api/v1/asset_provenance_records/stats" do
    it "returns counts for admins" do
      sign_in admin
      create(:asset_provenance_record, :verified)
      create(:asset_provenance_record, :ai_modified)
      create(:asset_provenance_record, :missing)
      get "/api/v1/asset_provenance_records/stats"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("verified", "ai_modified", "missing", "signed", "unchecked")
    end
  end

  # ---------------------------------------------------------------------------
  # bulk_upsert (gateway secret)
  # ---------------------------------------------------------------------------

  describe "POST /api/v1/asset_provenance_records/bulk_upsert" do
    let(:asset) { create(:asset) }

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("GATEWAY_SECRET", nil).and_return("gw-secret")
    end

    it "rejects requests without the gateway secret" do
      post "/api/v1/asset_provenance_records/bulk_upsert",
           params: { records: [] }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects wrong secret" do
      post "/api/v1/asset_provenance_records/bulk_upsert",
           params: { records: [] }, as: :json,
           headers: { "X-Gateway-Secret" => "wrong" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "upserts records with a correct secret" do
      expect {
        post "/api/v1/asset_provenance_records/bulk_upsert",
             params: {
               records: [ {
                 asset_id:       asset.uuid,
                 manifest_status: "verified",
                 claim_generator: "Adobe Photoshop 25.0",
                 is_ai_modified:  false,
               } ],
             }, as: :json,
             headers: { "X-Gateway-Secret" => "gw-secret" }
      }.to change(AssetProvenanceRecord, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["upserted"]).to eq(1)
    end

    it "updates an existing record (idempotent upsert)" do
      record = create(:asset_provenance_record, :missing, asset: asset)
      post "/api/v1/asset_provenance_records/bulk_upsert",
           params: {
             records: [ { asset_id: asset.uuid, manifest_status: "verified" } ],
           }, as: :json,
           headers: { "X-Gateway-Secret" => "gw-secret" }
      expect(record.reload.manifest_status).to eq("verified")
      expect(response).to have_http_status(:ok)
    end

    it "skips records with unknown asset_id and reports skipped count" do
      post "/api/v1/asset_provenance_records/bulk_upsert",
           params: { records: [ { asset_id: "00000000-0000-0000-0000-000000000000", manifest_status: "verified" } ] },
           as: :json, headers: { "X-Gateway-Secret" => "gw-secret" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["skipped"]).to eq(1)
    end
  end
end
