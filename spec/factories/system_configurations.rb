FactoryBot.define do
  factory :system_configuration do
    sequence(:key) { |n| "config_key_\#{n}" }
    data_type { "string" }
    value { "some-value" }
    description { "A test configuration" }
  end
end
