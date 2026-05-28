FactoryBot.define do
  factory :report_definition do
    name { "MyString" }
    report_type { "MyString" }
    query_config { "" }
    active { false }
  end
end
