FactoryBot.define do
  factory :asset do
    sequence(:title) { |n| "Asset #{n}" }
    association :user
    folder { nil }
    status { :ready }
    sequence(:uuid) { SecureRandom.uuid }
    properties do
      {
        "description"  => "A sample asset",
        "usage_terms"  => "Internal Use Only",
        "alt_text"     => "",
        "tags"         => []
      }
    end
    deleted_at { nil }

    trait :trashed do
      deleted_at { Time.current }
    end
  end
end
