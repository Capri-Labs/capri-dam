# frozen_string_literal: true

FactoryBot.define do
  factory :c2pa_configuration do
    gateway_c2pa_enabled    { false }
    auto_verify_on_ingest   { false }
    auto_sign_on_ingest     { false }
    require_c2pa_on_import  { false }
    ai_disclosure_required  { true }
    signing_issuer_name     { "Capri DAM" }
    signing_org             { "Acme Corp" }
    trust_store_urls        { [] }
    verification_strictness { "lenient" }
    policy_notes            { nil }

    trait :enabled do
      gateway_c2pa_enabled  { true }
      auto_verify_on_ingest { true }
    end

    trait :strict do
      gateway_c2pa_enabled    { true }
      verification_strictness { "strict" }
    end
  end
end
