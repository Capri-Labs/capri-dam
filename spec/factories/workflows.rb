FactoryBot.define do
  factory :workflow do
    sequence(:name) { |n| "Workflow \#{n}" }
    description { "Test workflow" }
    status { :draft }
    trigger_type { "manual" }
  end
end
