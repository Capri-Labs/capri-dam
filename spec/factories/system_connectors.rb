FactoryBot.define do
  factory :system_connector do
    name { "MyString" }
    provider_type { "MyString" }
    endpoint { "MyString" }
    auth_token { "MyString" }
    tdm_sanitation { false }
    status { "MyString" }
    last_sync { "2026-06-03 17:02:35" }
    assets_imported { 1 }
  end
end
