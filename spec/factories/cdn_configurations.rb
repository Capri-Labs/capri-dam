FactoryBot.define do
  factory :cdn_configuration do
    provider { "MyString" }
    is_active { false }
    settings { "MyText" }
  end
end
