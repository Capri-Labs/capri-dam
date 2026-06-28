class WorkflowStep < ApplicationRecord
  # Advanced types: 'approval', 'notification', 'automated_action'
  belongs_to :workflow

  # Node types supported by the Visual Workflow Designer v2
  NODE_TYPES = %w[
    approval
    email_notification in_app_notification slack teams sms
    webhook secure_webhook api_call
    set_status add_tags remove_tags move_asset copy_asset archive publish update_metadata
    ai_metadata generate_thumbnail cdn_sync
    delay condition
  ].freeze

  # node_types that require human interaction (approval family)
  APPROVAL_NODE_TYPES = %w[approval].freeze

  # node_types that require an endpoint URL
  URL_NODE_TYPES = %w[webhook secure_webhook api_call].freeze

  validates :step_type, presence: true
  validates :position,  presence: true
  validates :node_type, inclusion: { in: NODE_TYPES }, allow_nil: true

  # Approval steps need a real assignee; automated steps default to 'system'.
  validates :assignee_type, presence: true
  validates :assignee_id,   presence: true
  validates :logic,         presence: true

  # Config-level validations for automated steps
  validate :step_config_complete, if: -> { node_type.present? && !APPROVAL_NODE_TYPES.include?(node_type) }

  # Logic to determine who can perform this step
  def resolve_assignee
    case assignee_type
    when "user"  then User.find_by(id: assignee_id)
    when "group" then UserGroup.find_by(id: assignee_id)
    end
  end

  private

  def step_config_complete
    cfg = (step_config || {}).with_indifferent_access
    case node_type
    when *URL_NODE_TYPES
      errors.add(:step_config, "must include a non-blank URL for #{node_type}") if cfg[:url].blank?
    when "email_notification"
      errors.add(:step_config, "must include a subject for email_notification") if cfg[:subject].blank?
    end
  end
end
