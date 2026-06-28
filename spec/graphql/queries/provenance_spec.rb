# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GraphQL — C2PA Provenance queries", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user)  { create(:user) }

  def gql(query, variables: {}, user: admin)
    sign_in user if user
    post "/graphql",
         params:  { query: query, variables: variables.to_json },
         headers: { "Content-Type" => "application/json" },
         as:      :json
    JSON.parse(response.body)
  end

  # ---------------------------------------------------------------------------
  # c2paConfiguration
  # ---------------------------------------------------------------------------

  describe "query c2paConfiguration" do
    let(:query) do
      <<~GQL
        query {
          c2paConfiguration {
            id
            gatewayC2paEnabled
            autoVerifyOnIngest
            aiDisclosureRequired
            verificationStrictness
            policyNotes
          }
        }
      GQL
    end

    it "returns the singleton config for admins" do
      result = gql(query)
      expect(result["errors"]).to be_nil
      cfg = result.dig("data", "c2paConfiguration")
      expect(cfg).to include(
        "gatewayC2paEnabled"   => false,
        "verificationStrictness" => "lenient",
        "aiDisclosureRequired" => true
      )
    end

    it "returns an authorization error for non-admins" do
      result = gql(query, user: user)
      errors = result["errors"] || []
      data   = result.dig("data", "c2paConfiguration")
      # Either the field is nil (object-level auth) or errors array is populated
      expect(errors.any? || data.nil?).to be(true)
    end

    it "returns an authorization error for unauthenticated requests" do
      post "/graphql",
           params:  { query: query },
           headers: { "Content-Type" => "application/json" },
           as:      :json
      body = JSON.parse(response.body)
      cfg  = body.dig("data", "c2paConfiguration")
      expect(cfg).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # assetProvenanceRecords
  # ---------------------------------------------------------------------------

  describe "query assetProvenanceRecords" do
    let(:query) do
      <<~GQL
        query($status: String, $aiModified: Boolean, $limit: Int) {
          assetProvenanceRecords(status: $status, aiModified: $aiModified, limit: $limit) {
            id
            manifestStatus
            isAiModified
            claimGenerator
            verifiedAt
          }
        }
      GQL
    end

    let!(:verified)   { create(:asset_provenance_record, :verified) }
    let!(:ai_rec)     { create(:asset_provenance_record, :ai_modified) }

    it "returns all records (up to limit) for admins" do
      result = gql(query, variables: { limit: 10 })
      expect(result["errors"]).to be_nil
      records = result.dig("data", "assetProvenanceRecords")
      expect(records.size).to eq(2)
    end

    it "filters by status" do
      result = gql(query, variables: { status: "verified", limit: 10 })
      records = result.dig("data", "assetProvenanceRecords")
      expect(records.map { |r| r["manifestStatus"] }).to all(eq("verified"))
    end

    it "filters by ai_modified flag" do
      result = gql(query, variables: { aiModified: true, limit: 10 })
      records = result.dig("data", "assetProvenanceRecords")
      expect(records.map { |r| r["isAiModified"] }).to all(be(true))
    end

    it "returns nil / error for non-admins" do
      result = gql(query, variables: { limit: 10 }, user: user)
      data   = result.dig("data", "assetProvenanceRecords")
      errors = result["errors"] || []
      expect(errors.any? || data.nil?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # assetProvenanceRecord (single)
  # ---------------------------------------------------------------------------

  describe "query assetProvenanceRecord" do
    let(:query) do
      <<~GQL
        query($id: ID!) {
          assetProvenanceRecord(id: $id) {
            id
            manifestStatus
            errorDetail
          }
        }
      GQL
    end

    let!(:record) { create(:asset_provenance_record, :invalid) }

    it "returns the record for admins" do
      result = gql(query, variables: { id: record.id })
      expect(result["errors"]).to be_nil
      data = result.dig("data", "assetProvenanceRecord")
      expect(data).to include("manifestStatus" => "invalid")
    end

    it "returns nil for an unknown id" do
      result = gql(query, variables: { id: 0 })
      expect(result.dig("data", "assetProvenanceRecord")).to be_nil
    end

    it "returns nil / error for non-admins" do
      result = gql(query, variables: { id: record.id }, user: user)
      data   = result.dig("data", "assetProvenanceRecord")
      errors = result["errors"] || []
      expect(errors.any? || data.nil?).to be(true)
    end
  end
end
