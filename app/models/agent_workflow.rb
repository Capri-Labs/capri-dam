# frozen_string_literal: true

# An AgentWorkflow defines a single autonomous AI agent pipeline.
#
# When +active+ is true the DAM broadcasts the workflow config to the AI Gateway
# over Redis (`ai_gateway_events`), which then listens for the configured
# +trigger_event+ and executes the agent chain.
#
# == Trigger events
#
# | Value                | Description                              |
# |----------------------|------------------------------------------|
# | `asset.staged`       | Any new upload that completes staging    |
# | `asset.updated`      | Any asset metadata update                |
# | `schedule.nightly`   | Daily cron at midnight UTC               |
# | `manual`             | Only via the "Trigger Now" UI action     |
#
# @see AgentExecution
class AgentWorkflow < ApplicationRecord
  TRIGGER_EVENTS = %w[asset.staged asset.updated schedule.nightly manual].freeze

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  belongs_to :created_by, class_name: "User", foreign_key: :created_by_id, optional: true
  has_many   :agent_executions, dependent: :destroy

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :name,          presence: true, length: { maximum: 120 }
  validates :trigger_event, presence: true, inclusion: { in: TRIGGER_EVENTS }
  validates :agent_model,   presence: true

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  scope :active_only,  -> { where(active: true) }
  scope :listening,    -> { active_only }
  scope :by_trigger,   ->(event) { where(trigger_event: event) }

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  after_commit :broadcast_to_gateway, on: [ :create, :update ]
  after_commit :broadcast_deactivation, on: :destroy

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------

  # Computes a simple reliability score from recent executions (last 100).
  #
  # @return [Float, nil] percentage (0–100) or nil when no executions exist
  def reliability
    recent = agent_executions.order(started_at: :desc).limit(100)
    return nil if recent.none?

    successes = recent.count { |e| e.status == "success" }
    (successes.to_f / recent.size * 100).round(1)
  end

  # Returns the average duration (ms) of the last 100 completed executions.
  #
  # @return [Float, nil]
  def avg_duration_ms
    agent_executions
      .where.not(duration_ms: nil)
      .order(started_at: :desc)
      .limit(100)
      .average(:duration_ms)
      &.round(0)
      &.to_i
  end

  # Gateway-ready payload for the workflow toggle event.
  #
  # @return [Hash]
  def to_gateway_payload
    {
      event:    active? ? "agent_workflow.activated" : "agent_workflow.deactivated",
      workflow: {
        id:           id,
        name:         name,
        trigger:      trigger_event,
        agent_model:  agent_model,
        tools:        tools_enabled,
        metadata:     metadata,
      },
    }
  end

  private

  def broadcast_to_gateway
    payload = to_gateway_payload.to_json
    Sidekiq.redis { |conn| conn.publish("ai_gateway_events", payload) }
  rescue StandardError => e
    Rails.logger.warn("[AgentWorkflow##{id}] gateway broadcast skipped: #{e.message}")
  end

  def broadcast_deactivation
    payload = { event: "agent_workflow.removed", workflow: { id: id } }.to_json
    Sidekiq.redis { |conn| conn.publish("ai_gateway_events", payload) }
  rescue StandardError => e
    Rails.logger.warn("[AgentWorkflow##{id}] removal broadcast skipped: #{e.message}")
  end
end
