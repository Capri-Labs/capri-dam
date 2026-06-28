class WorkflowStep < ApplicationRecord
  # Advanced types: 'approval', 'notification', 'automated_action'
  belongs_to :workflow

  # Node types supported by the Visual Workflow Designer v2
  NODE_TYPES = %w[
    approval email_notification in_app_notification
    slack teams sms
    webhook secure_webhook api_call
    set_status add_tags remove_tags move_asset copy_asset archive publish update_metadata
    ai_metadata generate_thumbnail cdn_sync
    delay condition
  ].freeze

  # Ensuring all core fields are present before saving
  validates :step_type, presence: true
  validates :assignee_type, presence: true
  validates :assignee_id, presence: true
  validates :logic, presence: true
  validates :position, presence: true
  validates :node_type, inclusion: { in: NODE_TYPES }, allow_nil: true

  # Logic to determine who can perform this step
  def resolve_assignee
    # Future logic: if assignee_type is 'Group', find all users in that group
  end
end
