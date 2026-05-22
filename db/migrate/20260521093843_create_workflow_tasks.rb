class CreateWorkflowTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :workflow_tasks do |t|
      t.references :workflow_instance, null: false, foreign_key: true
      t.references :workflow_step, null: false, foreign_key: true

      # The specific human assigned to this task
      t.references :user, null: false, foreign_key: true

      # pending, approved, rejected, or canceled (if logic was 'Any' and someone else approved first)
      t.string :status, default: 'pending', null: false

      # The audit trail comment left by the user upon approval/rejection
      t.text :comment

      # Timestamp for calculating how long this specific user took to respond
      t.datetime :completed_at

      t.timestamps
    end

    # Ensure fast lookups for a user's specific inbox dashboard
    add_index :workflow_tasks, [:user_id, :status]
  end
end