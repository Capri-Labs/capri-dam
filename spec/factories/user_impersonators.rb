FactoryBot.define do
  factory :user_impersonator do
    association :user,         factory: :user
    association :impersonator, factory: :user
  end
end
