FactoryBot.define do
  factory :system_connector do
    sequence(:name) { |n| "Connector \#{n}" }
    provider_type { "aem" }
    endpoint { "https://dam.example.com" }
    auth_token { "secret-token" }
    tdm_sanitation { false }
    status { "active" }
    assets_imported { 0 }

    trait :ftp do
      provider_type { "ftp" }
      endpoint { "ftp.example.com" }
    end

    trait :jwt_service_account do
      credential_type { "jwt_service_account" }
      auth_token { nil }
      credentials_payload do
        {
          "client_id"            => "cm-p123-integration-0",
          "client_secret"        => "p8e-test-secret",
          "private_key"          => OpenSSL::PKey::RSA.new(2048).to_pem,
          "technical_account_id" => "ABC123@techacct.adobe.com",
          "org_id"               => "ORG123@AdobeOrg",
          "ims_endpoint"         => "ims-na1.adobelogin.com",
          "metascopes"           => "ent_aem_cloud_api",
        }
      end
    end
  end
end
