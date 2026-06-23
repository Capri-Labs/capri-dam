FactoryBot.define do
  factory :cdn_configuration do
    sequence(:provider) { |n| "provider_\#{n}" }
    is_active { false }
    settings { { "api_key" => "abc123" } }
  end
end
