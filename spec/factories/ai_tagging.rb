FactoryBot.define do
  factory :ai_tagging_run do
    asset
    status  { "queued" }
    profile { "general_subject" }
    trigger { "manual" }

    trait :running do
      status { "running" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      completed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      error_message { "Gateway unavailable" }
      completed_at { Time.current }
    end
  end

  factory :ai_tag_suggestion do
    ai_tagging_run
    asset { ai_tagging_run.asset }
    sequence(:label) { |n| "label_#{n}" }
    confidence { 0.9 }
    state { "pending" }

    trait :accepted do
      state { "accepted" }
      decided_at { Time.current }
    end

    trait :dismissed do
      state { "dismissed" }
      decided_at { Time.current }
    end
  end
end
