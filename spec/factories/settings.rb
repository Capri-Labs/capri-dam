FactoryBot.define do
  factory :setting do
    sequence(:key) { |n| "setting_\#{n}" }
    value { { "enabled" => true } }
  end
end
