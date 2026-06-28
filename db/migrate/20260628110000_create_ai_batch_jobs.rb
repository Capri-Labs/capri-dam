# frozen_string_literal: true

# Creates the ai_batch_jobs table that backs the "AI Batch Tasks" screen at
# /ai/tasks (legacy /ai/batch).
#
# Each row is one on-demand, admin-configured AI batch run.  The available task
# types and target datasets are defined declaratively in
# Ai::BatchTaskRegistry so new AI tasks can be added without a schema change.
#
# Lifecycle:  queued → running → completed | failed | cancelled
#
# The worker resolves the target dataset, broadcasts a dispatch event to the AI
# Gateway over Redis (`ai_gateway_events`), and the gateway streams progress
# back via POST /api/v1/ai_batch_jobs/:id/progress (gateway-secret auth).
class CreateAiBatchJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_batch_jobs do |t|
      # Registry key of the AI task to run, e.g. "metadata_extraction".
      t.string  :task_type,       null: false

      # Registry key of the target dataset, e.g. "missing_metadata".
      t.string  :target_scope,    null: false

      # Lifecycle: queued | running | paused | completed | failed | cancelled
      t.string  :status,          null: false, default: "queued"

      # Number of items processed in parallel per gateway batch.
      t.integer :concurrency,     null: false, default: 25

      # Task-specific options forwarded verbatim to the gateway payload.
      t.jsonb   :options,         null: false, default: {}

      # Progress counters maintained by the gateway via the progress endpoint.
      t.integer :total_count,     null: false, default: 0
      t.integer :processed_count, null: false, default: 0
      t.integer :succeeded_count, null: false, default: 0
      t.integer :failed_count,    null: false, default: 0

      # Error detail when status == "failed".
      t.text    :error_message

      t.datetime :started_at
      t.datetime :completed_at

      # Audit: who launched this job.
      t.bigint  :created_by_id

      t.timestamps
    end

    add_index :ai_batch_jobs, :status
    add_index :ai_batch_jobs, :task_type
    add_index :ai_batch_jobs, :created_by_id
    add_index :ai_batch_jobs, :created_at
    add_foreign_key :ai_batch_jobs, :users, column: :created_by_id
  end
end

