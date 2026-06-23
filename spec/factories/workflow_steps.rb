FactoryBot.define do
  factory :workflow_step do
    association :workflow
    position { 1 }
    step_type { "approval" }
    assignee_type { "User" }
    assignee_id { 1 }
    logic { "any" }
    title { "Brand Review" }
  end
end
