FactoryBot.define do
  factory :asset_download do
    sequence(:name) { |n| "download_#{n}" }
    association :user
    folder_ids { [] }
    asset_ids { [] }
    status { :pending }
    total_items { 0 }
    processed_items { 0 }
    file_count { 0 }
    byte_size { 0 }

    trait :completed do
      status { :completed }
      total_items { 3 }
      processed_items { 3 }
      file_count { 1 }
      byte_size { 2048 }
      expires_at { 7.days.from_now }
    end

    trait :processing do
      status { :processing }
      total_items { 5 }
      processed_items { 2 }
    end

    trait :expired do
      status { :completed }
      expires_at { 1.day.ago }
    end
  end
end
