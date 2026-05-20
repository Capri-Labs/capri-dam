FactoryBot.define do
  factory :workflow_instance do
    asset { nil }
    workflow { nil }
    status { "MyString" }
    current_step_id { 1 }
    last_action_by_id { 1 }
    audit_log { "" }
  end
end
