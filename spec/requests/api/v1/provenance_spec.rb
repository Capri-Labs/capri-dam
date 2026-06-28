# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Api::V1::C2PA Configuration", type: :request do
  let(:admin) { create(:user, :admin) }

  path "/api/v1/c2pa_configuration" do
    get "Show C2PA policy configuration (admin only)" do
      tags     "Content Provenance / C2PA"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Configuration returned" do
        schema "$ref" => "#/components/schemas/C2paConfiguration"
        before { sign_in admin }
        run_test!
      end
    end

    patch "Update C2PA policy configuration (admin only)" do
      tags     "Content Provenance / C2PA"
      consumes "application/json"
      produces "application/json"
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          c2pa_configuration: {
            type: :object,
            properties: {
              gateway_c2pa_enabled:    { type: :boolean },
              auto_verify_on_ingest:   { type: :boolean },
              auto_sign_on_ingest:     { type: :boolean },
              require_c2pa_on_import:  { type: :boolean },
              ai_disclosure_required:  { type: :boolean },
              signing_issuer_name:     { type: :string },
              signing_org:             { type: :string },
              verification_strictness: { type: :string, enum: %w[lenient strict] },
              policy_notes:            { type: :string },
              trust_store_urls:        { type: :array, items: { type: :string } },
            },
          },
        },
      }

      response "200", "Configuration updated" do
        before { sign_in admin }
        let(:payload) { { c2pa_configuration: { gateway_c2pa_enabled: true } } }
        run_test!
      end

      response "422", "Validation failed" do
        before { sign_in admin }
        let(:payload) { { c2pa_configuration: { verification_strictness: "bogus" } } }
        run_test!
      end
    end
  end
end

RSpec.describe "Api::V1::AssetProvenanceRecords", type: :request do
  let(:admin) { create(:user, :admin) }

  path "/api/v1/asset_provenance_records" do
    get "List provenance records (admin only)" do
      tags     "Content Provenance / C2PA"
      produces "application/json"
      security [ Bearer: [] ]

      parameter name: :status,      in: :query, type: :string,  required: false
      parameter name: :ai_modified, in: :query, type: :boolean, required: false
      parameter name: :page,        in: :query, type: :integer, required: false

      response "200", "Records returned" do
        schema type: :object,
               properties: {
                 total:    { type: :integer },
                 page:     { type: :integer },
                 per_page: { type: :integer },
                 records:  { type: :array, items: { "$ref" => "#/components/schemas/AssetProvenanceRecord" } },
               }
        before do
          sign_in admin
          create(:asset_provenance_record, :verified)
        end
        run_test!
      end
    end
  end

  path "/api/v1/asset_provenance_records/stats" do
    get "Dashboard statistics (admin only)" do
      tags     "Content Provenance / C2PA"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Stats returned" do
        schema type: :object,
               properties: {
                 total_assets: { type: :integer },
                 verified:     { type: :integer },
                 ai_modified:  { type: :integer },
                 missing:      { type: :integer },
                 invalid:      { type: :integer },
                 signed:       { type: :integer },
                 unchecked:    { type: :integer },
               }
        before { sign_in admin }
        run_test!
      end
    end
  end

  path "/api/v1/asset_provenance_records/{id}" do
    parameter name: :id, in: :path, type: :integer

    get "Fetch a single provenance record (admin only)" do
      tags     "Content Provenance / C2PA"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Record returned" do
        schema "$ref" => "#/components/schemas/AssetProvenanceRecord"
        let(:record) { create(:asset_provenance_record, :verified) }
        let(:id)     { record.id }
        before { sign_in admin }
        run_test!
      end

      response "404", "Not found" do
        let(:id) { 0 }
        before { sign_in admin }
        run_test!
      end
    end
  end

  path "/api/v1/asset_provenance_records/bulk_upsert" do
    post "Bulk-upsert provenance results (AI Gateway, secret-authenticated)" do
      tags        "Content Provenance / C2PA"
      consumes    "application/json"
      produces    "application/json"
      description "Internal endpoint called by the AI Gateway to write per-asset C2PA results. Authenticated via X-Gateway-Secret header."

      parameter name: "X-Gateway-Secret", in: :header, type: :string, required: true
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[records],
        properties: {
          records: {
            type: :array,
            items: {
              type: :object,
              properties: {
                asset_id:                { type: :string, description: "Asset UUID" },
                manifest_status:         { type: :string, enum: %w[unchecked verified ai_generated ai_modified missing invalid signed error] },
                claim_generator:         { type: :string },
                is_ai_modified:          { type: :boolean },
                ai_tools_used:           { type: :array, items: { type: :string } },
                verified_at:             { type: :string, format: "date-time" },
                signed_at:               { type: :string, format: "date-time" },
                signer_name:             { type: :string },
                signer_cert_fingerprint: { type: :string },
                error_detail:            { type: :string },
                manifest_data:           { type: :object },
              },
            },
          },
        },
      }

      response "200", "Records upserted" do
        let(:asset) { create(:asset) }
        let(:payload) do
          { records: [ { asset_id: asset.uuid, manifest_status: "verified" } ] }
        end
        let("X-Gateway-Secret") { "test-secret" }
        before do
          allow(ENV).to receive(:fetch).and_call_original
          allow(ENV).to receive(:fetch).with("GATEWAY_SECRET", nil).and_return("test-secret")
        end
        run_test!
      end

      response "401", "Invalid or missing gateway secret" do
        let(:asset)   { create(:asset) }
        let(:payload) { { records: [ { asset_id: asset.uuid, manifest_status: "verified" } ] } }
        let("X-Gateway-Secret") { "wrong" }
        run_test!
      end
    end
  end
end
