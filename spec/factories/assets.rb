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
        "usage_terms"  => Rights::UsageTerms::DEFAULT,
        "alt_text"     => "",
        "tags"         => [],
      }
    end
    deleted_at { nil }

    trait :trashed do
      deleted_at { Time.current }
    end

    trait :externally_distributable do
      usage_terms { "royalty_free" }
    end

    trait :license_expired do
      usage_terms { "rights_managed" }
      license_expires_at { 1.day.ago }
    end
  end
end
