FactoryBot.define do
  factory :collection do
    sequence(:name) { |n| "Collection \#{n}" }
    description { "A test collection" }
    association :user
    collection_type { "manual" }
    deleted_at { nil }
  end
end
