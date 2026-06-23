class MetadataExport < ApplicationRecord
  # Microsoft Excel worksheet row ceiling (minus 1 for the header row).
  # Exports larger than this are split across multiple CSV files.
  MAX_ROWS_PER_FILE = 1_048_575

  # Generated CSVs expire (and are cleaned up) after this period.
  RETENTION_PERIOD = 30.days

  belongs_to :user
  belongs_to :folder, optional: true

  # One export may produce several CSV files when the asset count exceeds
  # MAX_ROWS_PER_FILE, so we attach many.
  has_many_attached :files

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  validates :name, presence: true
  validates :property_mode, inclusion: { in: %w[all selective] }

  scope :recent,      -> { order(created_at: :desc) }
  scope :expired,     -> { where(expires_at: ..Time.current) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  # The set of metadata property keys to export for this run.
  def selective?
    property_mode == "selective"
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end
end

