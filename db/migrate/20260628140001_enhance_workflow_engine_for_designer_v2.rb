# frozen_string_literal: true

# Enhances the workflow engine for the Visual Workflow Designer v2:
#
#   1. workflow_steps.node_type  — distinguishes between 'approval', 'webhook',
#      'notification', 'slack', 'teams', 'set_status', 'add_tags', 'move_asset',
#      'delay', 'condition', etc. (defaults to 'approval' for backward-compat).
#
#   2. workflow_steps.step_config (jsonb) — stores node-type-specific config
#      (e.g. webhook URL+secret, notification body, status to set, tag list).
#
#   3. workflow_instances.cancelled_by_id — records the admin who force-cancelled
#      an instance so the audit log can surface who killed it and why.
#
#   4. workflow_instances.cancel_reason — free-text reason stored for audit trail.
#
# Fully reversible via change/remove_column.
class EnhanceWorkflowEngineForDesignerV2 < ActiveRecord::Migration[8.1]
  def change
    # Step node type & rich config
    add_column :workflow_steps, :node_type,   :string, default: "approval", null: false
    add_column :workflow_steps, :step_config, :jsonb,  default: {}, null: false
    add_index  :workflow_steps, :node_type

    # Admin force-cancel audit columns
    add_column :workflow_instances, :cancelled_by_id, :bigint
    add_column :workflow_instances, :cancel_reason,   :text
    add_index  :workflow_instances, :cancelled_by_id

    add_foreign_key :workflow_instances, :users, column: :cancelled_by_id, on_delete: :nullify
  end
end
