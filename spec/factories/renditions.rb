FactoryBot.define do
  factory :rendition do
    asset { nil }
    storage_backend { nil }
    storage_key { "MyString" }
    kind { "MyString" }
    width { 1 }
    height { 1 }
    file_size { "" }
    content_type { "MyString" }
    metadata { "" }
  end
end
