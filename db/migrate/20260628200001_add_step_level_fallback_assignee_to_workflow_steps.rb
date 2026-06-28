# frozen_string_literal: true

# Moves escalation ownership from the workflow level to the step level.
#
# Context:
#   The Visual Workflow Designer v2 already surfaces a "Fallback Assignee" picker
#   on every ApprovalNode.  Previously that UI data was thrown away because the
#   workflow_steps table had no columns to store it; the WorkflowAdvancerService
#   instead read the workflow-level fallback_assignee_type/id.
#
# This migration adds the two columns to workflow_steps so that each approval
# step can carry its own escalation path.  The workflow-level columns
# (fallback_assignee_type / fallback_assignee_id on the workflows table) are
# kept intact for backward-compatibility with any external integrations, but
# are no longer surfaced in the designer UI.
#
# Reversible via `change`.
class AddStepLevelFallbackAssigneeToWorkflowSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :workflow_steps, :fallback_assignee_type, :string, default: "user"
    add_column :workflow_steps, :fallback_assignee_id,   :string, default: ""

    add_index :workflow_steps, :fallback_assignee_type
  end
end
