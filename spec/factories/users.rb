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

    # Super-admin — member of the 'super-administrators' group.
    # The after(:create) hook mirrors the group-based check in User#super_admin?
    trait :super_admin do
      admin { true }
      role  { "admin" }

      after(:create) do |user|
        group = UserGroup.find_or_create_by!(
          slug: "super-administrators",
          name: "Super Administrators",
        ) { |g| g.is_system = true }
        user.user_groups << group unless user.user_groups.include?(group)
      end
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
