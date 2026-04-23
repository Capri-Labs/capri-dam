FactoryBot.define do
  factory :user do
    name     { "Test User" }
    sequence(:username) { |n| "user_#{n}" }
    sequence(:email)    { |n| "test_#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    admin    { false } # Change to true in individual tests if needed
  end
end