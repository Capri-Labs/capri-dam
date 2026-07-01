FactoryBot.define do
  factory :inbox_message do
    association :recipient, factory: :user
    sender { nil }
    association :email_template
    subject { Faker::Lorem.sentence }
    body_html { "<p>#{Faker::Lorem.paragraph}</p>" }
    body_text { Faker::Lorem.paragraph }
    message_type { 'notification' }
    read_at { nil }
    archived_at { nil }
    starred_at { nil }
    metadata { {} }

    trait :unread do
      read_at { nil }
    end

    trait :read do
      read_at { 1.hour.ago }
    end

    trait :starred do
      starred_at { 1.hour.ago }
    end

    trait :archived do
      archived_at { 1.hour.ago }
    end

    trait :mention do
      message_type { 'mention' }
    end

    trait :workflow do
      message_type { 'workflow' }
    end

    trait :with_sender do
      association :sender, factory: :user
    end
  end
end
