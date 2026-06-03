FactoryBot.define do
  factory :quarantined_asset do
    system_connector { nil }
    original_payload { "" }
    rejection_reason { "MyText" }
    status { "MyString" }
  end
end
