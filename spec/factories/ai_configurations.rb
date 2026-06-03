FactoryBot.define do
  factory :ai_configuration do
    active_provider { "MyString" }
    generation_model { "MyString" }
    embedding_model { "MyString" }
    monthly_budget_usd { "9.99" }
    current_spend_usd { "9.99" }
    system_prompt { "MyText" }
    fallback_to_local { false }
  end
end
