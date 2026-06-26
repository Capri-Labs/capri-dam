# frozen_string_literal: true

module Types
  # GraphQL type representing the current state of the background bin purge job.
  class BinPurgeStatusType < Types::BaseObject
    description "Current state and last-run results for the automated Recycle Bin purge."

    field :status,       String, null: false,
          description: '"idle" | "queued" | "running" | "completed" | "failed"'
    field :last_ran_at,  GraphQL::Types::ISO8601DateTime, null: true,
          description: "Timestamp when the last purge run completed."
    field :started_at,   GraphQL::Types::ISO8601DateTime, null: true,
          description: "Timestamp when the current or last run started."
    field :triggered_by, Types::JsonType, null: true,
          description: "Who triggered the run: { user_id, user_name, user_email, source, triggered_at }."
    field :last_results, Types::JsonType, null: true,
          description: "Results of the last completed purge run (deleted, skipped, failed counts, etc.)."
    field :policy,       Types::BinRetentionPolicyType, null: false,
          description: "The active retention policy that will be applied on the next run."
  end
end
