FactoryBot.define do
  factory :collection_rule do
    collection { nil }
    semantic_prompt { "MyText" }
    similarity_threshold { "9.99" }
    metadata_filters { "" }
    active { false }
  end
end
