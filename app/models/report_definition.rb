class ReportDefinition < ApplicationRecord
  has_many :report_snapshots, dependent: :destroy

  BUILT_IN_TYPES = %w[
    asset_library workflow_compliance storage_usage user_activity ai_coverage
    duplicates license_expiry collections audit_trail migration
  ].freeze

  validates :name, presence: true, length: { maximum: 120 }
  validates :name, uniqueness: { case_sensitive: false }
  validates :report_type, presence: true,
                          format: { with: /\A[\w\-]+\z/, message: "only letters, numbers, hyphens and underscores allowed" }

  scope :active,    -> { where(active: true) }
  scope :built_in,  -> { where(report_type: BUILT_IN_TYPES) }
  scope :custom,    -> { where.not(report_type: BUILT_IN_TYPES) }

  def description
    query_config&.dig("description")
  end

  def built_in?
    BUILT_IN_TYPES.include?(report_type)
  end
end
