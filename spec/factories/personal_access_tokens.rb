FactoryBot.define do
  factory :personal_access_token do
    association :user

    name      { "Test Token" }
    scopes    { "read" }
    last_four { "abcd" }
    active    { true }

    # token_digest is required — generate a random one for factory-created records
    token_digest { Digest::SHA256.hexdigest(SecureRandom.hex(16)) }

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :revoked do
      active { false }
    end

    trait :write do
      scopes { "write" }
    end
  end
end
