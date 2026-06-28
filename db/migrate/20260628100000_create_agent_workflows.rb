# frozen_string_literal: true

# Creates the agent_workflows and agent_executions tables that back the
# "Agent Automations" screen at /ai/agents.
#
# agent_workflows  — each row is one autonomous AI agent pipeline definition.
#                    When active: true, the DAM broadcasts the workflow config
#                    to the AI Gateway over Redis so the gateway can listen for
#                    the configured trigger event and execute the agent chain.
#
# agent_executions — immutable audit log.  One row per agent run, written by
#                    the AI Gateway calling POST /api/v1/agent_workflows/:id/executions.
class CreateAgentWorkflows < ActiveRecord::Migration[8.1]
  def change
    # -------------------------------------------------------------------------
    # agent_workflows
    # -------------------------------------------------------------------------
    create_table :agent_workflows do |t|
      # Human-readable name shown in the UI.
      t.string  :name,          null: false

      # Optional free-text description of what the workflow does.
      t.text    :description

      # The event that fires this workflow, e.g.:
      #   "asset.staged"       – every new upload
      #   "asset.updated"      – metadata change
      #   "schedule.nightly"   – daily cron at midnight UTC
      #   "manual"             – only on demand
      t.string  :trigger_event, null: false

      # LLM/agent model identifier sent to the gateway, e.g. "gpt-4o-mini".
      t.string  :agent_model,   null: false

      # JSON array of tool names the agent should load, e.g.:
      #   ["VisualContextExtractor", "SEOTaxonomyMapper"]
      t.jsonb   :tools_enabled, null: false, default: []

      # When false, the gateway ignores this workflow.
      t.boolean :active,        null: false, default: false

      # Optional additional config forwarded verbatim to the gateway payload.
      # Use for threshold overrides, prompt templates, etc.
      t.jsonb   :metadata,      null: false, default: {}

      # Audit: who created this workflow.
      t.bigint  :created_by_id

      t.timestamps
    end

    add_index :agent_workflows, :trigger_event
    add_index :agent_workflows, :active
    add_index :agent_workflows, :created_by_id
    add_foreign_key :agent_workflows, :users, column: :created_by_id

    # -------------------------------------------------------------------------
    # agent_executions
    # -------------------------------------------------------------------------
    create_table :agent_executions do |t|
      t.bigint  :agent_workflow_id, null: false

      # "event" (triggered by asset event), "manual", "scheduled"
      t.string  :trigger_type,      null: false, default: "event"

      # The raw event payload forwarded by the gateway (e.g. { asset_id: "..." }).
      t.jsonb   :trigger_payload,   null: false, default: {}

      # Lifecycle: running → success | warning | failed
      t.string  :status,            null: false, default: "running"

      # Structured output from the gateway (tags written, assets quarantined, …)
      t.jsonb   :output,            null: false, default: {}

      # Human-readable summary, e.g. "Mapped 4 tags to summer_hero.jpg"
      t.text    :summary

      # Error detail when status == "failed"
      t.text    :error_message

      # Wall-clock duration measured by the gateway (milliseconds).
      t.integer :duration_ms

      t.datetime :started_at,  null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :completed_at

      t.timestamps
    end

    add_index :agent_executions, :agent_workflow_id
    add_index :agent_executions, :status
    add_index :agent_executions, :started_at
    add_foreign_key :agent_executions, :agent_workflows
  end
end
