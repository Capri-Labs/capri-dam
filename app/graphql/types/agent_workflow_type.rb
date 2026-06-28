# frozen_string_literal: true

module Types
  class AgentWorkflowType < Types::BaseObject
    description "An autonomous AI agent pipeline that fires on DAM system events or on schedule."

    field :id,              ID,                              null: false
    field :name,            String,                          null: false
    field :description,     String,                          null: true
    field :trigger_event,   String,                          null: false, description: "asset.staged | asset.updated | schedule.nightly | manual"
    field :agent_model,     String,                          null: false
    field :tools_enabled,   [ String ],                      null: false
    field :active,          Boolean,                         null: false
    field :metadata,        Types::JsonType,                 null: true
    field :reliability,     Float,                           null: true, description: "Success rate (0–100) over the last 100 runs."
    field :avg_duration_ms, Integer,                         null: true
    field :execution_count, Integer,                         null: false
    field :created_at,      GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at,      GraphQL::Types::ISO8601DateTime, null: false
    field :recent_executions, [ Types::AgentExecutionType ], null: false,
          description: "The 20 most recent execution records." do
      argument :limit, Integer, required: false, default_value: 20
    end

    def execution_count
      object.agent_executions.size
    end

    def recent_executions(limit:)
      object.agent_executions.recent.limit(limit.clamp(1, 100))
    end

    def self.authorized?(object, context)
      super && context[:current_user].present?
    end
  end
end
