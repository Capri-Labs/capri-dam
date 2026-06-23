FactoryBot.define do
  factory :ingestion_item do
    association :ingestion_batch
    sequence(:original_filename) { |n| "file_\#{n}.jpg" }
    sequence(:file_hash) { |n| "sha256_\#{n}" }
    file_size { 1024 }
    status { :pending }
  end
end
