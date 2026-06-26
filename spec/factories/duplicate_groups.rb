FactoryBot.define do
  factory :duplicate_group do
    sequence(:checksum) { |n| Digest::SHA256.hexdigest("test_file_#{n}") }
    status      { "pending" }
    total_count { 0 }

    trait :resolved do
      status            { "resolved" }
      resolution_action { "kept_all" }
      resolved_at       { Time.current }
      association :resolved_by, factory: :user
    end

    trait :dismissed do
      status      { "dismissed" }
      resolved_at { Time.current }
      association :resolved_by, factory: :user
    end
  end

  factory :duplicate_group_asset do
    association :duplicate_group
    association :asset
    is_original { false }

    trait :original do
      is_original { true }
    end
  end
end
