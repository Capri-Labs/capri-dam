# frozen_string_literal: true

module Types
  class AgentExecutionType < Types::BaseObject
    description "A single execution record of an agent workflow run."

    field :id,              ID,                              null: false
    field :trigger_type,    String,                          null: false
    field :trigger_payload, Types::JsonType,                 null: true
    field :status,          String,                          null: false, description: "running | success | warning | failed"
    field :summary,         String,                          null: true
    field :output,          Types::JsonType,                 null: true
    field :error_message,   String,                          null: true
    field :duration_ms,     Integer,                         null: true
    field :started_at,      GraphQL::Types::ISO8601DateTime, null: false
    field :completed_at,    GraphQL::Types::ISO8601DateTime, null: true

    def self.authorized?(object, context)
      super && context[:current_user].present?
    end
  end
end
