FactoryBot.define do
  factory :report_definition do
    sequence(:name) { |n| "Report \#{n}" }
    report_type { "asset_inventory" }
    query_config { {} }
    active { true }
  end
end
