# frozen_string_literal: true

module Types
  class AiBatchJobType < Types::BaseObject
    description "An on-demand AI batch task run launched from the /ai/tasks screen."

    field :id,               ID,                              null: false
    field :task_type,        String,                          null: false, description: "Registry key, e.g. metadata_extraction"
    field :task_label,       String,                          null: true
    field :target_scope,     String,                          null: false
    field :status,           String,                          null: false, description: "queued | running | paused | completed | failed | cancelled"
    field :concurrency,      Integer,                         null: false
    field :options,          Types::JsonType,                 null: true
    field :total_count,      Integer,                         null: false
    field :processed_count,  Integer,                         null: false
    field :succeeded_count,  Integer,                         null: false
    field :failed_count,     Integer,                         null: false
    field :progress_percent, Integer,                         null: false
    field :error_message,    String,                          null: true
    field :created_by,       String,                          null: true
    field :started_at,       GraphQL::Types::ISO8601DateTime, null: true
    field :completed_at,     GraphQL::Types::ISO8601DateTime, null: true
    field :created_at,       GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at,       GraphQL::Types::ISO8601DateTime, null: false

    def task_label
      object.task_descriptor&.label
    end

    def created_by
      object.created_by&.email
    end

    # Reads are admin-only — mirrors the /ai/tasks screen access policy.
    def self.authorized?(object, context)
      super && context[:current_user]&.admin?
    end
  end
end
