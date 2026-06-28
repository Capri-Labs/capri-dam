# frozen_string_literal: true

module Types
  class WorkflowStepType < Types::BaseObject
    description "A single step within a workflow blueprint."

    field :id,           ID,                   null: false
    field :title,        String,               null: true
    field :description,  String,               null: true
    field :step_type,    String,               null: false
    field :node_type,    String,               null: true,  description: "Visual canvas node type (e.g. email_notification, condition)"
    field :position,     Integer,              null: false
    field :assignee_type, String,              null: false
    field :assignee_id,  String,               null: false
    field :fallback_assignee_type, String,     null: true,  description: "Step-level escalation assignee type ('user' or 'group')"
    field :fallback_assignee_id,   String,     null: true,  description: "Step-level escalation assignee id (used when the primary assignee is unavailable)"
    field :logic,        String,               null: false,  description: "'any' or 'all'"
    field :deadline_days, Integer,             null: true
    field :step_config,  Types::JsonType,      null: true,  description: "Node-specific configuration JSON"
    field :created_at,   GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at,   GraphQL::Types::ISO8601DateTime, null: false

    def self.authorized?(object, context)
      super && context[:current_user].present?
    end
  end
end
