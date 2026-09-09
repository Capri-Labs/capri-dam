FactoryBot.define do
  factory :entity do
    entity_type { "person" }
    sequence(:name) { |n| "Entity #{n}" }
    description { nil }
    properties { {} }
    external_ids { {} }

    trait :person do
      entity_type { "person" }
    end

    trait :product do
      entity_type { "product" }
    end

    trait :place do
      entity_type { "place" }
    end

    trait :campaign do
      entity_type { "campaign" }
    end

    trait :brand do
      entity_type { "brand" }
    end

    trait :event do
      entity_type { "event" }
    end
  end

  factory :entity_alias do
    association :entity
    sequence(:alias_text) { |n| "alias #{n}" }
    source { "manual" }
  end

  factory :asset_entity do
    association :asset
    association :entity
    relationship { "depicts" }
    source { "manual" }

    trait :from_tag do
      source { "tag_resolution" }
      confidence { nil }
    end

    trait :from_ai do
      source { "ai" }
      confidence { 0.8 }
    end

    trait :confirmed do
      confirmed_at { Time.current }
    end
  end
end
