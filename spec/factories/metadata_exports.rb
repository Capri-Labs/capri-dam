FactoryBot.define do
  factory :metadata_export do
    sequence(:name) { |n| "export_#{n}" }
    association :user
    folder { nil }
    include_subfolders { true }
    property_mode { "all" }
    selected_properties { [] }
    status { :pending }
    total_assets { 0 }
    file_count { 0 }

    trait :selective do
      property_mode { "selective" }
      selected_properties { %w[description copyright] }
    end

    trait :completed do
      status { :completed }
      total_assets { 5 }
      file_count { 1 }
      expires_at { 30.days.from_now }
    end

    trait :expired do
      status { :completed }
      expires_at { 1.day.ago }
    end
  end
end

