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
  end
end
