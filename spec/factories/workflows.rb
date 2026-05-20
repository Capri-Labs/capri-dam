FactoryBot.define do
  factory :workflow do
    name { "MyString" }
    description { "MyText" }
    status { 1 }
    trigger_type { "MyString" }
    metadata { "" }
    created_by_id { 1 }
    updated_by_id { 1 }
  end
end
