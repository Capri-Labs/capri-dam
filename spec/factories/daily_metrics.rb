FactoryBot.define do
  factory :daily_metric do
    metric_date { "2026-05-27" }
    metric_name { "MyString" }
    metric_value { 1 }
    metadata { "" }
  end
end
