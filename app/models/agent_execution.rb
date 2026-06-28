# frozen_string_literal: true

# Immutable audit record of a single agent run.
#
# Rows are written by the AI Gateway calling:
#   POST /api/v1/agent_workflows/:id/executions
#
# @see AgentWorkflow
class AgentExecution < ApplicationRecord
  STATUSES = %w[running success warning failed].freeze

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  belongs_to :agent_workflow

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :status,       presence: true, inclusion: { in: STATUSES }
  validates :trigger_type, presence: true
  validates :started_at,   presence: true

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  scope :recent,    -> { order(started_at: :desc) }
  scope :completed, -> { where.not(status: "running") }
  scope :for_workflow, ->(wf_id) { where(agent_workflow_id: wf_id) }
end
