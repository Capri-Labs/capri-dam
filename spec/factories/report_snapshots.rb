FactoryBot.define do
  factory :report_snapshot do
    association :report_definition
    status { 1 }
    format { "csv" }
    parameters { {} }
  end
end
