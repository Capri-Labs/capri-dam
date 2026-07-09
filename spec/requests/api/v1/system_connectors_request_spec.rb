# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SystemConnectors coverage", type: :request do
  let(:admin) { create(:user, admin: true) }
  let(:user) { create(:user) }

  def json = response.parsed_body

  before do
    allow(PreFlightAnalysisWorker).to receive(:perform_async)
    allow(ExtractionWorker).to receive(:perform_async)
  end

  describe "GET /api/v1/system_connectors" do
    it "requires authentication and returns provider labels in newest-first order" do
      create(:system_connector, name: "Old", created_at: 2.days.ago)
      create(:system_connector, :ftp, name: "New", created_at: 1.hour.ago)

      get "/api/v1/system_connectors", as: :json
      expect(response).to have_http_status(:unauthorized)

      sign_in user
      get "/api/v1/system_connectors", as: :json

      expect(response).to have_http_status(:ok)
      expect(json.map { |connector| connector["name"] }).to eq(%w[New Old])
      expect(json.first["provider_label"]).to eq("FTP / SFTP")
    end

    it "returns a paginated shape when a page param is given" do
      15.times { |i| create(:system_connector, name: "Connector #{i}", created_at: i.hours.ago) }

      sign_in user
      get "/api/v1/system_connectors", params: { page: 2, per_page: 12 }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["connectors"].size).to eq(3)
      expect(json["pagination"]).to include(
        "page" => 2, "per_page" => 12, "total" => 15, "total_pages" => 2
      )
    end
  end

  describe "admin connector writes" do
    before { sign_in admin }

    it "creates connectors with server-managed defaults and reports validation errors" do
      post "/api/v1/system_connectors", params: {
        system_connector: { name: "Cloudinary", provider_type: "cloudinary", endpoint: "https://api.cloudinary.com", auth_token: "tok" },
      }, as: :json

      expect(response).to have_http_status(:created)
      expect(json).to include("name" => "Cloudinary", "status" => "idle", "assets_imported" => 0)

      post "/api/v1/system_connectors", params: { system_connector: { name: "Broken", provider_type: "nope" } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["errors"]).to be_present
    end

    it "updates without overwriting a blank auth token" do
      connector = create(:system_connector, auth_token: "keep-me")

      patch "/api/v1/system_connectors/#{connector.id}", params: {
        system_connector: { name: "Renamed", auth_token: "", endpoint: "https://renamed.example.com" },
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(connector.reload).to have_attributes(name: "Renamed", auth_token: "keep-me")
    end
  end

  describe "POST /api/v1/system_connectors/test_connection" do
    before { sign_in admin }

    it "rejects missing endpoints for non-Cloudinary providers" do
      post "/api/v1/system_connectors/test_connection", params: { provider_type: "aem" }, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(json).to include("success" => false, "message" => "Endpoint and credentials are required.")
    end

    it "returns success, failure, and adapter argument errors" do
      allow(IngestionAdapters::Factory).to receive(:test).with("cloudinary", { "cloud_name" => "demo" })
                                                    .and_return(success: true, message: "Connected")
      allow(IngestionAdapters::Factory).to receive(:test).with("aem", hash_including("endpoint" => "https://aem.example.com"))
                                                    .and_return(success: false, message: "Denied")
      allow(IngestionAdapters::Factory).to receive(:test).with("ftp", hash_including("endpoint" => "ftp.example.com"))
                                                    .and_raise(ArgumentError, "unsupported")

      post "/api/v1/system_connectors/test_connection", params: { provider_type: "cloudinary", cloud_name: "demo" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json).to include("success" => true, "message" => "Connected")

      post "/api/v1/system_connectors/test_connection", params: { provider_type: "aem", endpoint: "https://aem.example.com" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("success" => false, "message" => "Denied")

      post "/api/v1/system_connectors/test_connection", params: { provider_type: "ftp", endpoint: "ftp.example.com" }, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(json).to include("success" => false, "message" => "unsupported")
    end
  end

  describe "migration helpers" do
    before { sign_in admin }

    it "queues pre-flight analysis" do
      connector = create(:system_connector)

      post "/api/v1/system_connectors/pre_flight_analysis", params: { id: connector.id }, as: :json

      expect(response).to have_http_status(:accepted)
      expect(PreFlightAnalysisWorker).to have_received(:perform_async).with(connector.id)
    end

    it "rejects inactive migrations, starts active ones, and renders creation failures" do
      idle = create(:system_connector, status: "idle")
      active = create(:system_connector, status: "active", endpoint: "https://active.example.com", auth_token: "secret")

      post "/api/v1/system_connectors/#{idle.id}/start_migration", as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("Connector is not active.")

      post "/api/v1/system_connectors/#{active.id}/start_migration", as: :json
      expect(response).to have_http_status(:accepted)
      expect(json).to include("message" => "Migration started.")
      expect(ExtractionWorker).to have_received(:perform_async).with(IngestionBatch.last.id)
      expect(IngestionBatch.last.source_credentials).to include("endpoint" => "https://active.example.com", "auth_token" => "secret")

      allow(IngestionBatch).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(IngestionBatch.new))
      post "/api/v1/system_connectors/#{active.id}/start_migration", as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to be_present
    end

    it "scopes a migration to the requested source_path and records it on the batch" do
      active = create(:system_connector, status: "active", endpoint: "https://active.example.com", auth_token: "secret")

      post "/api/v1/system_connectors/#{active.id}/start_migration",
           params: { source_path: "/content/dam/US/marketing-assets/product-assets" }, as: :json

      expect(response).to have_http_status(:accepted)
      expect(IngestionBatch.last.source_path).to eq("/content/dam/US/marketing-assets/product-assets")
      expect(IngestionBatch.last.source_credentials).to include("root_path" => "/content/dam/US/marketing-assets/product-assets")
    end

    it "does not snapshot a token for jwt_service_account connectors so future chunk fetches always refresh live" do
      connector = create(:system_connector, :jwt_service_account, status: "active")

      post "/api/v1/system_connectors/#{connector.id}/start_migration", as: :json

      expect(response).to have_http_status(:accepted)
      expect(IngestionBatch.last.source_credentials).to eq({})
    end
  end

  describe "token lifecycle actions" do
    before { sign_in admin }

    it "refreshes an IMS access token on demand" do
      connector = create(:system_connector, :jwt_service_account)
      allow(Ims::JwtTokenExchangeService).to receive(:new).with(connector).and_return(
        instance_double(Ims::JwtTokenExchangeService, call: { access_token: "fresh", expires_at: 1.hour.from_now })
      )

      post "/api/v1/system_connectors/#{connector.id}/refresh_token", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["token_status"]).to eq("valid")
      expect(connector.reload.access_token).to eq("fresh")
    end

    it "rejects a token refresh for non-JWT connectors" do
      connector = create(:system_connector)

      post "/api/v1/system_connectors/#{connector.id}/refresh_token", as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "surfaces exchange errors from a failed refresh" do
      connector = create(:system_connector, :jwt_service_account)
      allow(Ims::JwtTokenExchangeService).to receive(:new).and_raise(Ims::JwtTokenExchangeService::Error, "invalid_client_secret")

      post "/api/v1/system_connectors/#{connector.id}/refresh_token", as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("invalid_client_secret")
    end

    it "revokes (locally clears) a cached access token" do
      connector = create(:system_connector, :jwt_service_account, access_token: "cached", access_token_expires_at: 1.hour.from_now)

      post "/api/v1/system_connectors/#{connector.id}/revoke_token", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["token_status"]).to eq("revoked")
      expect(connector.reload.access_token).to be_nil
    end
  end

  describe "creating a jwt_service_account connector from pasted Adobe integration JSON" do
    before { sign_in admin }

    let(:integration_json) do
      {
        integration: {
          imsEndpoint: "ims-na1.adobelogin.com",
          metascopes: "ent_aem_cloud_api",
          technicalAccount: { clientId: "cm-p1-integration-0", clientSecret: "p8e-secret" },
          email: "acct@techacct.adobe.com",
          id: "ACCTID@techacct.adobe.com",
          org: "ORGID@AdobeOrg",
          privateKey: OpenSSL::PKey::RSA.new(2048).to_pem,
          certificateExpirationDate: "2027-07-09T11:00:11.000Z",
        },
      }.to_json
    end

    it "parses the pasted JSON into credentials_payload and sets credential_type" do
      post "/api/v1/system_connectors", params: {
        system_connector: {
          name: "AEM JWT", provider_type: "aem", endpoint: "https://author-x.adobeaemcloud.com",
          integration_json: integration_json
        },
      }, as: :json

      expect(response).to have_http_status(:created)
      connector = SystemConnector.last
      expect(connector.credential_type).to eq("jwt_service_account")
      expect(connector.credentials_payload).to include("client_id" => "cm-p1-integration-0", "org_id" => "ORGID@AdobeOrg")
      # Secrets never leak back over the API
      expect(json).not_to have_key("credentials_payload")
    end
  end

  describe "additional update branches" do
    before { sign_in admin }

    it "replaces auth tokens when a non-blank value is provided" do
      connector = create(:system_connector, auth_token: 'old-secret')

      patch "/api/v1/system_connectors/#{connector.id}", params: {
        system_connector: { auth_token: 'new-secret' },
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(connector.reload.auth_token).to eq('new-secret')
    end

    it "returns validation errors for invalid updates" do
      connector = create(:system_connector)

      patch "/api/v1/system_connectors/#{connector.id}", params: {
        system_connector: { name: '' },
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['errors']).not_to be_empty
    end
  end
end
