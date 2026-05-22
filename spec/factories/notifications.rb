FactoryBot.define do
  factory :notification do
    user { nil }
    title { "MyString" }
    message { "MyString" }
    action_url { "MyString" }
    read_at { "2026-05-21 17:06:07" }
  end
end
