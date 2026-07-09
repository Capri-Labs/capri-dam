require "rails_helper"

RSpec.describe Ims::JwtTokenExchangeService do
  let(:private_key) { OpenSSL::PKey::RSA.new(2048).to_pem }
  let(:payload) do
    {
      "client_id"             => "cm-p123-integration-0",
      "client_secret"         => "p8e-secret",
      "private_key"           => private_key,
      "technical_account_id"  => "ABC123@techacct.adobe.com",
      "org_id"                => "ORG123@AdobeOrg",
      "ims_endpoint"          => "ims-na1.adobelogin.com",
      "metascopes"            => "ent_aem_cloud_api",
    }
  end
  let(:connector) do
    SystemConnector.new(
      name: "AEM JWT", provider_type: "aem", endpoint: "https://author-x.adobeaemcloud.com",
      credential_type: "jwt_service_account", credentials_payload: payload
    )
  end

  subject(:service) { described_class.new(connector) }

  describe "#call" do
    it "signs a JWT and exchanges it for an access token" do
      stub_request(:post, "https://ims-na1.adobelogin.com/ims/exchange/jwt")
        .to_return(status: 200, body: { access_token: "ims-access-token", expires_in: 86_400 }.to_json, headers: { "Content-Type" => "application/json" })

      result = service.call

      expect(result[:access_token]).to eq("ims-access-token")
      expect(result[:expires_at]).to be_within(5.seconds).of(Time.current + 86_400.seconds)
    end

    it "sends the client_id/client_secret/jwt_token as form params, never the raw private key" do
      stub = stub_request(:post, "https://ims-na1.adobelogin.com/ims/exchange/jwt")
        .with { |req| req.body.include?("client_id=") && req.body.include?("jwt_token=") && !req.body.include?(CGI.escape(private_key)) }
        .to_return(status: 200, body: { access_token: "tok", expires_in: 3600 }.to_json)

      service.call
      expect(stub).to have_been_requested
    end

    it "raises a descriptive error on non-2xx IMS responses" do
      stub_request(:post, "https://ims-na1.adobelogin.com/ims/exchange/jwt")
        .to_return(status: 401, body: { error: "invalid_client_secret" }.to_json)

      expect { service.call }.to raise_error(Ims::JwtTokenExchangeService::Error, /IMS token exchange failed/)
    end

    it "raises when required credential fields are missing" do
      connector.credentials_payload = payload.except("client_secret")

      expect { service.call }.to raise_error(Ims::JwtTokenExchangeService::Error, /Missing IMS credential fields: client_secret/)
    end

    it "raises a clear error for an invalid private key" do
      connector.credentials_payload = payload.merge("private_key" => "not-a-real-key")

      expect { service.call }.to raise_error(Ims::JwtTokenExchangeService::Error, /Invalid private key/)
    end
  end
end
