class AddDetailsToWorkflowSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :workflow_steps, :title, :string
    add_column :workflow_steps, :description, :text
    add_column :workflow_steps, :deadline_days, :integer
  end
end
