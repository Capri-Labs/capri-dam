# frozen_string_literal: true

module Types
  # GraphQL type representing the configurable Recycle Bin purge retention policy.
  class BinRetentionPolicyType < Types::BaseObject
    description "Configurable policy controlling automatic Recycle Bin purging."

    field :retention_days,    Integer, null: false,
          description: "Items deleted ≥ this many days ago are eligible for permanent removal."
    field :workflow_behavior, String,  null: false,
          description: '"skip" (default) or "force_terminate" — what to do when an asset has an active workflow.'
    field :batch_size,        Integer, null: false,
          description: "Number of items processed per database batch."
    field :notify_admins,     Boolean, null: false,
          description: "Send an in-app notification to all admins after each purge run."
    field :next_scheduled_at, GraphQL::Types::ISO8601DateTime, null: true,
          description: "Estimated next scheduled purge time (03:00 UTC daily)."
  end
end
