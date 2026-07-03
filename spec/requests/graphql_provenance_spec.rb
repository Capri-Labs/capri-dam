# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GraphQL Provenance queries", type: :request do
  let(:admin)  { create(:user, :admin) }
  let(:viewer) { create(:user) }

  def gql_post(query:, user:)
    sign_in(user)
    post "/graphql", params: { query: query }.to_json,
                     headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    JSON.parse(response.body)
  end

  # ---------------------------------------------------------------------------
  # c2paConfiguration
  # ---------------------------------------------------------------------------

  describe "c2paConfiguration query" do
    let(:query) { "{ c2paConfiguration { id gatewayC2paEnabled verificationStrictness } }" }

    it "returns config for an admin" do
      body = gql_post(query: query, user: admin)
      expect(body["errors"]).to be_nil
      expect(body.dig("data", "c2paConfiguration", "verificationStrictness")).to eq("lenient")
    end

    it "returns null for a non-admin" do
      body = gql_post(query: query, user: viewer)
      expect(body.dig("data", "c2paConfiguration")).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # assetProvenanceRecords
  # ---------------------------------------------------------------------------

  describe "assetProvenanceRecords query" do
    let!(:verified)   { create(:asset_provenance_record, :verified) }
    let!(:ai_mod)     { create(:asset_provenance_record, :ai_modified) }

    let(:list_query) do
      "{ assetProvenanceRecords { id manifestStatus isAiModified assetUuid } }"
    end

    it "returns records for an admin" do
      body = gql_post(query: list_query, user: admin)
      expect(body["errors"]).to be_nil
      expect(body.dig("data", "assetProvenanceRecords").size).to eq(2)
    end

    it "returns empty list for a non-admin" do
      body = gql_post(query: list_query, user: viewer)
      expect(body.dig("data", "assetProvenanceRecords")).to eq([])
    end

    it "filters by status" do
      query = '{ assetProvenanceRecords(status: "verified") { id manifestStatus } }'
      body  = gql_post(query: query, user: admin)
      statuses = body.dig("data", "assetProvenanceRecords").map { |r| r["manifestStatus"] }
      expect(statuses).to all(eq("verified"))
    end

    it "filters to ai-modified assets" do
      query = "{ assetProvenanceRecords(aiModified: true) { id isAiModified } }"
      body  = gql_post(query: query, user: admin)
      expect(body.dig("data", "assetProvenanceRecords").size).to eq(1)
      expect(body.dig("data", "assetProvenanceRecords", 0, "isAiModified")).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # assetProvenanceRecord (singular)
  # ---------------------------------------------------------------------------

  describe "assetProvenanceRecord query" do
    it "finds a record by id for an admin" do
      rec   = create(:asset_provenance_record, :signed)
      query = "{ assetProvenanceRecord(id: #{rec.id}) { id manifestStatus signerName } }"
      body  = gql_post(query: query, user: admin)
      expect(body.dig("data", "assetProvenanceRecord", "manifestStatus")).to eq("signed")
      expect(body.dig("data", "assetProvenanceRecord", "signerName")).to eq("Capri DAM")
    end

    it "returns null for a non-admin" do
      rec   = create(:asset_provenance_record, :verified)
      query = "{ assetProvenanceRecord(id: #{rec.id}) { id } }"
      body  = gql_post(query: query, user: viewer)
      expect(body.dig("data", "assetProvenanceRecord")).to be_nil
    end

    it "returns nil asset fields when the provenance record cannot load its asset" do
      rec = create(:asset_provenance_record, :verified)
      query = "{ assetProvenanceRecord(id: #{rec.id}) { id assetUuid assetTitle } }"
      allow_any_instance_of(AssetProvenanceRecord).to receive(:asset).and_return(nil) # rubocop:disable RSpec/AnyInstance

      body = gql_post(query: query, user: admin)

      expect(body.dig("data", "assetProvenanceRecord")).to include("assetUuid" => nil, "assetTitle" => nil)
    end
  end
end
