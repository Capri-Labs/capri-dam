FactoryBot.define do
  factory :transformation_preset do
    sequence(:name) { |n| "Preset \#{n}" }
    sequence(:slug) { |n| "preset-\#{n}" }
    params { { "width" => 100, "format" => "webp" } }
  end
end
