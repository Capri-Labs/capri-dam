FactoryBot.define do
  factory :scheduled_publish_action do
    association :asset
    association :created_by, factory: :user
    action_type { 'publish' }
    scheduled_at { 1.hour.from_now }
    status { :pending }
  end
end
