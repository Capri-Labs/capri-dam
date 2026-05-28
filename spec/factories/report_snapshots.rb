FactoryBot.define do
  factory :report_snapshot do
    report_definition { nil }
    status { 1 }
    format { "MyString" }
    parameters { "" }
    error_message { "MyText" }
  end
end
