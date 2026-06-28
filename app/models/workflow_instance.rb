class WorkflowInstance < ApplicationRecord
  belongs_to :asset
  belongs_to :workflow
  belongs_to :last_action_by,  class_name: "User", optional: true
  belongs_to :current_step,    class_name: "WorkflowStep", optional: true
  belongs_to :cancelled_by,    class_name: "User", foreign_key: "cancelled_by_id", optional: true

  has_many :workflow_tasks, dependent: :destroy

  TERMINAL_STATUSES = %w[completed rejected canceled].freeze

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  # Helper to update status and record who did it
  def transition_to!(new_status, user, note = nil)
    self.audit_log ||= []
    self.audit_log << {
      action:     new_status,
      user_id:    user.id,
      user_name:  user.full_name,
      timestamp:  Time.current,
      note:       note,
    }
    self.status          = new_status
    self.last_action_by  = user
    save!
  end

  # Admin force-cancel: halts everything and records who & why.
  def force_cancel!(admin_user, reason = nil)
    transaction do
      update!(
        status:           "canceled",
        completed_at:     Time.current,
        cancelled_by:     admin_user,
        cancel_reason:    reason,
        last_action_by:   admin_user,
      )
      workflow_tasks.where(status: "pending").update_all(
        status:       "canceled",
        comment:      "Force-cancelled by #{admin_user.email}: #{reason.presence || "Admin action"}",
        completed_at: Time.current,
      )
    end
  end
end
