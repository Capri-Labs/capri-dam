# frozen_string_literal: true

FactoryBot.define do
  factory :asset_provenance_record do
    association :asset
    manifest_status  { "unchecked" }
    manifest_data    { {} }
    claim_generator  { nil }
    is_ai_modified   { false }
    ai_tools_used    { [] }

    trait :verified do
      manifest_status { "verified" }
      claim_generator { "Adobe Photoshop 25.0" }
      verified_at     { 1.hour.ago }
    end

    trait :ai_generated do
      manifest_status { "ai_generated" }
      claim_generator { "Adobe Firefly 3.0" }
      is_ai_modified  { true }
      ai_tools_used   { [ "AdobeFirefly", "StableDiffusion" ] }
      verified_at     { 30.minutes.ago }
    end

    trait :ai_modified do
      manifest_status { "ai_modified" }
      claim_generator { "Adobe Photoshop 25.0" }
      is_ai_modified  { true }
      ai_tools_used   { [ "GenerativeFill" ] }
      verified_at     { 1.hour.ago }
    end

    trait :missing do
      manifest_status { "missing" }
    end

    trait :invalid do
      manifest_status { "invalid" }
      error_detail    { "Certificate chain verification failed" }
    end

    trait :signed do
      manifest_status         { "signed" }
      claim_generator         { "Capri DAM 1.0" }
      signer_name             { "Capri DAM" }
      signer_cert_fingerprint { "sha256:abc123def456" }
      signed_at               { 30.minutes.ago }
    end

    trait :error do
      manifest_status { "error" }
      error_detail    { "Gateway timeout after 30s" }
    end
  end
end
