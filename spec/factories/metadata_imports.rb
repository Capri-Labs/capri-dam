FactoryBot.define do
  factory :metadata_import do
    sequence(:name) { |n| "import_#{n}.csv" }
    association :user
    batch_size { 50 }
    field_separator { "," }
    multi_value_delimiter { "|" }
    launch_workflows { false }
    asset_path_column { "asset_path" }
    ignored_columns { [] }
    status { :pending }

    trait :completed do
      status { :completed }
      total_rows { 3 }
      success_count { 3 }
      failure_count { 0 }
      expires_at { 30.days.from_now }
    end

    trait :expired do
      status { :completed }
      expires_at { 1.day.ago }
    end
  end
end

