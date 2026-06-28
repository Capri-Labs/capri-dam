FactoryBot.define do
  factory :style_preset do
    sequence(:name) { |n| "Editorial #{n}" }
    sequence(:slug) { |n| "editorial-#{n}" }
    description  { "Clean, editorial style with high contrast." }
    active       { true }
    is_default   { false }
    style_params { { "tone" => "editorial", "palette" => [ "#1a1a1a", "#ffffff" ], "aspect_ratio" => "16:9" } }
    gateway_ref  { nil }
    synced_at    { nil }
    association  :created_by, factory: :user

    trait :default do
      is_default { true }
    end

    trait :inactive do
      active { false }
    end

    trait :synced do
      sequence(:gateway_ref) { |n| "gw-preset-#{n}" }
      synced_at { 1.hour.ago }
    end

    trait :stale do
      sequence(:gateway_ref) { |n| "gw-preset-stale-#{n}" }
      synced_at { 2.days.ago }
    end
  end
end
