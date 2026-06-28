# frozen_string_literal: true

module Types
  class WorkflowInstanceType < Types::BaseObject
    description "A runtime execution of a workflow blueprint against a specific asset."

    field :id,               ID,                              null: false
    field :status,           String,                          null: false
    field :started_at,       GraphQL::Types::ISO8601DateTime, null: true
    field :completed_at,     GraphQL::Types::ISO8601DateTime, null: true
    field :cancel_reason,    String,                          null: true
    field :audit_log,        [ Types::JsonType ],             null: false
    field :current_step,     Types::WorkflowStepType,         null: true
    field :workflow_id,      ID,                              null: false
    field :asset_id,         ID,                              null: false
    field :task_count,       Integer,                         null: false, description: "Total tasks created for this instance"
    field :pending_tasks,    Integer,                         null: false, description: "Tasks still awaiting a decision"
    field :created_at,       GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at,       GraphQL::Types::ISO8601DateTime, null: false

    def audit_log
      object.audit_log || []
    end

    def task_count
      object.workflow_tasks.size
    end

    def pending_tasks
      object.workflow_tasks.where(status: "pending").count
    end

    def self.authorized?(object, context)
      super && context[:current_user].present?
    end
  end
end
