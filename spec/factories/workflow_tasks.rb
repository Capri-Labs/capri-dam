FactoryBot.define do
  factory :workflow_task do
    association :workflow_instance
    association :user
    association :workflow_step
    status { "pending" }
  end
end
