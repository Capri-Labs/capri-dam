# db/migrate/20260513095132_create_workflow_instances.rb
class CreateWorkflowInstances < ActiveRecord::Migration[8.1]
  def change
    create_table :workflow_instances do |t|
      # Explicitly set type to :uuid to match the assets table
      t.references :asset, type: :uuid, null: false, foreign_key: true
      t.references :workflow, null: false, foreign_key: true

      t.string :status
      t.integer :current_step_id
      t.integer :last_action_by_id
      t.jsonb :audit_log

      t.timestamps
    end
  end
end