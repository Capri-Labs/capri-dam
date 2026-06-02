FactoryBot.define do
  factory :system_configuration do
    key { "MyString" }
    data_type { "MyString" }
    value { "MyText" }
    fallback_value { "MyText" }
    expires_at { "2026-06-02 11:27:55" }
    description { "MyString" }
    updated_by_id { 1 }
  end
end
