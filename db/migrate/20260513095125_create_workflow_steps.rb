class CreateWorkflowSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :workflow_steps do |t|
      t.references :workflow, null: false, foreign_key: true
      t.integer :position
      t.string :step_type
      t.string :assignee_type
      t.integer :assignee_id
      t.jsonb :configuration
      t.integer :updated_by_id

      t.timestamps
    end
  end
end
