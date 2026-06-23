FactoryBot.define do
  factory :collection_rule do
    association :collection
    semantic_prompt { "Find all beach photos" }
    similarity_threshold { 0.8 }
    active { true }
  end
end
