FactoryBot.define do
  factory :ingestion_batch do
    sequence(:name) { |n| "Batch \#{n}" }
    source_type { "aem" }
    status { :initializing }
    total_count { 0 }
    processed_count { 0 }
  end
end
