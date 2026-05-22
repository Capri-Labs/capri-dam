class AddReportingAndSnapshotToWorkflowInstances < ActiveRecord::Migration[7.1]
  def change
    add_column :workflow_instances, :started_at, :datetime
    add_column :workflow_instances, :completed_at, :datetime
    add_column :workflow_instances, :blueprint_snapshot, :jsonb, default: {}

    # Index for fast SLA/reporting queries (e.g., "Find all workflows started last month")
    add_index :workflow_instances, :started_at
    add_index :workflow_instances, :completed_at
  end
end