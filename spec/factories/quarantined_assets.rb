FactoryBot.define do
  factory :quarantined_asset do
    association :system_connector
    original_payload { { "filename" => "test.jpg" } }
    rejection_reason { "Duplicate detected" }
    status { "pending_review" }
  end
end
