FactoryBot.define do
  factory :storage_backend do
    name { "MyString" }
    provider_type { "MyString" }
    configuration { "" }
    encrypted_credentials { "MyText" }
    active { false }
  end
end
