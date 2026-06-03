FactoryBot.define do
  factory :ingestion_item do
    ingestion_batch { nil }
    original_filename { "MyString" }
    file_hash { "MyString" }
    file_size { 1 }
    status { 1 }
    legacy_metadata { "" }
    clean_properties { "" }
    error_log { "MyText" }
  end
end
