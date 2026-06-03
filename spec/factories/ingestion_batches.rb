FactoryBot.define do
  factory :ingestion_batch do
    name { "MyString" }
    source_type { "MyString" }
    status { 1 }
    total_count { 1 }
    processed_count { 1 }
    user_id { 1 }
  end
end
