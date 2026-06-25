FactoryBot.define do
  factory :user_group do
    sequence(:name) { |n| "Test Group #{n}" }
    description     { "A test group" }
    is_system       { false }
    slug            { nil }

    trait :system do
      is_system { true }
    end

    trait :everyone do
      name      { "everyone" }
      slug      { "everyone" }
      is_system { true }
    end

    trait :administrators do
      name      { "administrators" }
      slug      { "administrators" }
      is_system { true }
    end

    trait :super_administrators do
      name      { "super-administrators" }
      slug      { "super-administrators" }
      is_system { true }
    end
  end
end

