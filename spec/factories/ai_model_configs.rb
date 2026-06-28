FactoryBot.define do
  factory :ai_model_config do
    name         { "GPT-4o Vision" }
    provider     { "openai" }
    model_id     { "gpt-4o" }
    capability   { "generation" }
    enabled      { true }
    is_default   { false }
    config_params { {} }
    health_status { "unknown" }
    metadata      { {} }

    trait :embedding do
      name       { "Text Embedding 3 Small" }
      model_id   { "text-embedding-3-small" }
      capability { "embedding" }
    end

    trait :vision do
      name       { "LLaVA Vision" }
      provider   { "ollama" }
      model_id   { "llava-1.6" }
      capability { "vision" }
    end

    trait :style_transfer do
      name       { "SDXL Style Transfer" }
      provider   { "huggingface" }
      model_id   { "stabilityai/stable-diffusion-xl-base-1.0" }
      capability { "style_transfer" }
    end

    trait :healthy do
      health_status    { "healthy" }
      health_latency_ms { 120 }
      last_health_check_at { Time.current }
    end

    trait :unhealthy do
      health_status  { "unhealthy" }
      error_message  { "Connection refused" }
      last_health_check_at { 1.hour.ago }
    end

    trait :default do
      is_default { true }
    end

    trait :disabled do
      enabled { false }
    end
  end
end
