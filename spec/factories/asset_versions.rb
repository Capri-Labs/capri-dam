FactoryBot.define do
  factory :asset_version do
    association :asset
    sequence(:version_number) { |n| n }
    action_type { "initial_upload" }
    properties  { {} }

    # Trait that stamps a SHA-256 checksum into properties (used in duplicate specs).
    trait :with_checksum do
      transient { checksum { Digest::SHA256.hexdigest(SecureRandom.hex) } }
      properties { { "checksum_sha256" => checksum } }
    end
  end
end
