# frozen_string_literal: true

FactoryBot.define do
  factory :image_profile do
    sequence(:name) { |n| "Image Profile #{n}" }

    unsharp_mask do
      { 'amount' => 1.75, 'radius' => 0.2, 'threshold' => 2 }
    end

    crop_type               { 'none' }
    responsive_crop_enabled { false }
    responsive_crops        { [] }
    swatch_enabled          { false }
    swatch_width            { 100 }
    swatch_height           { 100 }
    deleted_at              { nil }

    trait :with_smart_crop do
      crop_type               { 'smart_crop' }
      responsive_crop_enabled { true }
      responsive_crops do
        [
          { 'name' => 'Large',  'width' => 1260, 'height' => 720 },
          { 'name' => 'Medium', 'width' => 700,  'height' => 525 },
          { 'name' => 'Small',  'width' => 400,  'height' => 400 },
        ]
      end
    end

    trait :with_swatch do
      swatch_enabled { true }
      swatch_width   { 100 }
      swatch_height  { 100 }
    end

    trait :full do
      crop_type               { 'smart_crop' }
      responsive_crop_enabled { true }
      responsive_crops do
        [
          { 'name' => 'Large',  'width' => 1260, 'height' => 720 },
          { 'name' => 'Small',  'width' => 400,  'height' => 400 },
        ]
      end
      swatch_enabled { true }
      swatch_width   { 80 }
      swatch_height  { 80 }
    end

    trait :deleted do
      deleted_at { 1.day.ago }
    end
  end
end
