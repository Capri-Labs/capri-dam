FactoryBot.define do
  factory :workflow_instance do
    association :asset
    association :workflow
    status { "in_progress" }
    audit_log { [] }
  end
end
