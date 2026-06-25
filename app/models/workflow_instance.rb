class WorkflowInstance < ApplicationRecord
  belongs_to :asset
  belongs_to :workflow
  belongs_to :last_action_by, class_name: "User", optional: true
  belongs_to :current_step, class_name: "WorkflowStep", optional: true

  # Helper to update status and record who did it
  def transition_to!(new_status, user, note = nil)
    self.audit_log ||= []
    self.audit_log << {
      action: new_status,
      user_id: user.id,
      user_name: user.full_name,
      timestamp: Time.current,
      note: note,
    }
    self.status = new_status
    self.last_action_by = user
    save!
  end

  has_many :workflow_tasks, dependent: :destroy
end
