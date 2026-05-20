class FixWorkflowStepColumns < ActiveRecord::Migration[7.1]
  def change
    # Add columns to workflow_steps only if they don't exist
    add_column :workflow_steps, :title, :string unless column_exists?(:workflow_steps, :title)
    add_column :workflow_steps, :description, :text unless column_exists?(:workflow_steps, :description)
    add_column :workflow_steps, :logic, :string unless column_exists?(:workflow_steps, :logic)
    add_column :workflow_steps, :deadline_days, :integer unless column_exists?(:workflow_steps, :deadline_days)

    # Ensure step_type and assignee fields exist (they usually come from the initial model gen)
    add_column :workflow_steps, :step_type, :string unless column_exists?(:workflow_steps, :step_type)
    add_column :workflow_steps, :assignee_type, :string unless column_exists?(:workflow_steps, :assignee_type)
    add_column :workflow_steps, :assignee_id, :string unless column_exists?(:workflow_steps, :assignee_id)
  end
end