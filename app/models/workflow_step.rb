class WorkflowStep < ApplicationRecord
  # Advanced types: 'approval', 'notification', 'automated_action'
  belongs_to :workflow

  # Tasks generated for this step by running workflow instances. Destroying a
  # step (e.g. when it is removed in the Visual Designer) must cascade to its
  # tasks, otherwise the workflow_tasks -> workflow_steps foreign key blocks
  # the delete with a PG::ForeignKeyViolation.
  has_many :workflow_tasks, dependent: :destroy

  # Node types supported by the Visual Workflow Designer v2
  NODE_TYPES = %w[
    approval
    email_notification in_app_notification slack teams sms
    webhook secure_webhook api_call
    set_status add_tags remove_tags move_asset copy_asset archive publish update_metadata
    ai_metadata generate_thumbnail cdn_sync
    delay condition switch
  ].freeze

  # node_types that require human interaction (approval family)
  APPROVAL_NODE_TYPES = %w[approval].freeze

  # node_types that require an endpoint URL
  URL_NODE_TYPES = %w[webhook secure_webhook api_call].freeze

  # Custom-node (plugin SDK) types are namespaced "plugin:<key>". They are
  # validated against a registered CustomNodeDefinition rather than the static
  # NODE_TYPES list so tenants can extend the catalogue without a code change.
  PLUGIN_NODE_TYPE = /\Aplugin:[a-z0-9_]+\z/

  validates :step_type, presence: true
  validates :position,  presence: true
  validate  :node_type_supported

  # Approval steps need a real assignee; automated steps default to 'system'.
  validates :assignee_type, presence: true
  validates :assignee_id,   presence: true
  validates :logic,         presence: true

  # Config-level validations for automated steps
  validate :step_config_complete, if: -> { node_type.present? && !APPROVAL_NODE_TYPES.include?(node_type) }

  # Resolve the primary assignee for this step.
  def resolve_assignee
    case assignee_type
    when "user"  then User.find_by(id: assignee_id)
    when "group" then UserGroup.find_by(id: assignee_id)
    end
  end

  # Resolve the per-step fallback assignee (used when the primary assignee
  # cannot be found or is unavailable).
  def resolve_fallback_assignee
    case fallback_assignee_type
    when "user"  then User.find_by(id: fallback_assignee_id)
    when "group" then UserGroup.find_by(id: fallback_assignee_id)
    end
  end

  # Returns true when a meaningful step-level fallback has been configured.
  def has_step_fallback?
    fallback_assignee_id.present? && fallback_assignee_id != "0"
  end

  # Returns true when this step is a custom-node (plugin SDK) step.
  def plugin?
    node_type.to_s.match?(PLUGIN_NODE_TYPE)
  end

  private

  # node_type may be nil (legacy approval rows), one of the built-in NODE_TYPES,
  # or a namespaced plugin type ("plugin:<key>") registered via the SDK.
  def node_type_supported
    return if node_type.nil?
    return if NODE_TYPES.include?(node_type)
    return if plugin?

    errors.add(:node_type, "is not a supported node type")
  end

  def step_config_complete
    cfg = (step_config || {}).with_indifferent_access
    case node_type
    when *URL_NODE_TYPES
      errors.add(:step_config, "must include a non-blank URL for #{node_type}") if cfg[:url].blank?
    when "email_notification"
      errors.add(:step_config, "must include a subject for email_notification") if cfg[:subject].blank?
    when "switch"
      errors.add(:step_config, "must include a field to evaluate for switch") if cfg[:field].blank?
      errors.add(:step_config, "must include at least one case for switch") if Array(cfg[:cases]).empty?
    end
  end
end
