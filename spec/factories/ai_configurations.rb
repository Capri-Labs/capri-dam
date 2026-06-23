FactoryBot.define do
  factory :ai_configuration do
    active_provider { "openai" }
    generation_model { "gpt-4o" }
    embedding_model { "text-embedding-3-small" }
    monthly_budget_usd { 100.0 }
    current_spend_usd { 0.0 }
    system_prompt { "You are an enterprise data steward." }
    fallback_to_local { true }
  end
end
