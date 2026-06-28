FactoryBot.define do
  factory :agent_workflow do
    sequence(:name) { |n| "Agent Workflow #{n}" }
    description    { "Automatically enriches asset metadata using AI." }
    trigger_event  { "asset.staged" }
    agent_model    { "gpt-4o-mini" }
    tools_enabled  { %w[VisualContextExtractor SEOTaxonomyMapper] }
    active         { false }
    metadata       { {} }
    association :created_by, factory: :user

    trait :active do
      active { true }
    end

    trait :scheduled do
      trigger_event { "schedule.nightly" }
      agent_model   { "llama-3-local" }
    end

    trait :manual do
      trigger_event { "manual" }
    end
  end

  factory :agent_execution do
    association :agent_workflow
    trigger_type    { "event" }
    trigger_payload { { "asset_id" => SecureRandom.uuid } }
    status          { "success" }
    summary         { "Mapped 4 semantic tags to summer_hero.jpg" }
    output          { { "tags_added" => 4 } }
    duration_ms     { 1400 }
    started_at      { Time.current }
    completed_at    { Time.current }

    trait :running do
      status       { "running" }
      completed_at { nil }
      summary      { nil }
    end

    trait :failed do
      status        { "failed" }
      error_message { "Gateway timeout after 30s" }
      summary       { nil }
    end

    trait :warning do
      status  { "warning" }
      summary { "Quarantined GettyImages_Draft.png (watermark detected)" }
    end
  end
end
