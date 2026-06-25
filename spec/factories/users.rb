FactoryBot.define do
  factory :user do
    first_name { "Test" }
    last_name  { "User" }
    name       { "Test User" }
    sequence(:username) { |n| "user_#{n}" }
    sequence(:email)    { |n| "test_#{n}@example.com" }
    password              { "password123" }
    password_confirmation { "password123" }
    admin  { false }
    active { true }
    role   { "viewer" }

    trait :admin do
      admin { true }
      role  { "admin" }
    end

    trait :sso do
      sequence(:provider) { "keycloak_openid" }
      sequence(:uid)      { |n| "keycloak-uid-#{n}" }
      name { "SSO User" }
    end

    trait :inactive do
      active { false }
    end
  end
end

