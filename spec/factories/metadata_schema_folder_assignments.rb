FactoryBot.define do
  factory :metadata_schema_folder_assignment do
    association :metadata_schema
    folder_id { SecureRandom.uuid }
  end
end
