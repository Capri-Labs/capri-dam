FactoryBot.define do
  factory :notification do
    association :user
    title { "New task assigned" }
    message { "Please review the asset" }
    action_url { "/workflows/dashboard" }
    read_at { nil }

    trait :read do
      read_at { Time.current }
    end
  end
end
