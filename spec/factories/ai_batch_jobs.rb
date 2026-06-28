FactoryBot.define do
  factory :ai_batch_job do
    task_type    { "metadata_extraction" }
    target_scope { "all_assets" }
    status       { "queued" }
    concurrency  { 25 }
    options      { {} }
    total_count     { 0 }
    processed_count { 0 }
    succeeded_count { 0 }
    failed_count    { 0 }
    association :created_by, factory: :user

    trait :running do
      status      { "running" }
      total_count { 100 }
      processed_count { 40 }
      succeeded_count { 38 }
      failed_count    { 2 }
      started_at  { Time.current }
    end

    trait :completed do
      status          { "completed" }
      total_count     { 100 }
      processed_count { 100 }
      succeeded_count { 98 }
      failed_count    { 2 }
      started_at      { 2.minutes.ago }
      completed_at    { Time.current }
    end

    trait :failed do
      status        { "failed" }
      error_message { "Gateway unreachable" }
      completed_at  { Time.current }
    end

    trait :embedding_backfill do
      task_type    { "embedding_backfill" }
      target_scope { "missing_embeddings" }
    end
  end
end
