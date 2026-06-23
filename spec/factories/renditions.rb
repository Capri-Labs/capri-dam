FactoryBot.define do
  factory :rendition do
    association :asset
    association :storage_backend
    sequence(:storage_key) { |n| "renditions/\#{n}.jpg" }
    kind { "thumbnail" }
    width { 200 }
    height { 200 }
    file_size { 1024 }
    content_type { "image/jpeg" }
  end
end
