FactoryBot.define do
  factory :folder do
    sequence(:name) { |n| "Folder #{n}" }
    user { create(:user) }
    parent { nil }
    path { nil }
    deleted_at { nil }

    trait :trashed do
      deleted_at { Time.current }
    end
  end
end
