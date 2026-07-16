FactoryBot.define do
  factory :collection_rule do
    association :collection
    semantic_prompt { "Find all beach photos" }
    similarity_threshold { 0.8 }
    active { true }

    trait :metadata do
      match_mode { "metadata" }
      semantic_prompt { nil }
      metadata_filters { { "status" => "approved" } }
    end

    trait :hybrid do
      match_mode { "hybrid" }
      metadata_filters { { "status" => "approved" } }
    end
  end
end
