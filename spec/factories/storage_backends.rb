FactoryBot.define do
  factory :storage_backend do
    sequence(:name) { |n| "Backend \#{n}" }
    provider_type { "local" }
    configuration { { "root" => "storage/" } }
    active { false }
  end
end
