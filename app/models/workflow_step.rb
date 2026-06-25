class WorkflowStep < ApplicationRecord
  # Advanced types: 'approval', 'notification', 'automated_action'
  belongs_to :workflow

  # Ensuring all core fields are present before saving
  validates :step_type, presence: true
  validates :assignee_type, presence: true
  validates :assignee_id, presence: true
  validates :logic, presence: true
  validates :position, presence: true

  # Logic to determine who can perform this step
  def resolve_assignee
    # Future logic: if assignee_type is 'Group', find all users in that group
  end
end
