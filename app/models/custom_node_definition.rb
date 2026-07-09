class CustomNodeDefinition < ApplicationRecord
  KEY_FORMAT = /\A[a-z0-9_]+\z/
  STATUSES = %w[draft enabled disabled].freeze
  CIRCUIT_BREAKER_THRESHOLD = 5

  belongs_to :created_by, class_name: "User", optional: true

  validates :key, presence: true, format: { with: KEY_FORMAT }, uniqueness: true
  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :config_schema_shape
  validate :enabled_runtime_endpoint_is_https

  scope :enabled, -> { where(status: "enabled") }

  def node_type
    "plugin:#{key}"
  end

  def enabled?
    status == "enabled"
  end

  def disabled?
    status == "disabled"
  end

  def draft?
    status == "draft"
  end

  def circuit_open?
    failure_count.to_i >= CIRCUIT_BREAKER_THRESHOLD
  end

  private

  def config_schema_shape
    unless config_schema.is_a?(Array)
      errors.add(:config_schema, "must be an array of field descriptors")
      return
    end

    config_schema.each_with_index do |field, index|
      next if field.is_a?(Hash) && field["key"].present? && field["type"].present?

      errors.add(:config_schema, "field #{index + 1} must include key and type")
    end
  end

  def enabled_runtime_endpoint_is_https
    return unless enabled?

    url = runtime.is_a?(Hash) ? runtime["endpoint_url"].to_s : ""
    uri = URI.parse(url)
    return if uri.is_a?(URI::HTTPS) && uri.host.present?

    errors.add(:runtime, "endpoint_url must be an HTTPS URL when enabled")
  rescue URI::InvalidURIError
    errors.add(:runtime, "endpoint_url must be an HTTPS URL when enabled")
  end
end
