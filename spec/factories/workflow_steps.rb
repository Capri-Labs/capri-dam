FactoryBot.define do
  factory :workflow_step do
    workflow { nil }
    position { 1 }
    step_type { "MyString" }
    assignee_type { "MyString" }
    assignee_id { 1 }
    configuration { "" }
    updated_by_id { 1 }
  end
end
