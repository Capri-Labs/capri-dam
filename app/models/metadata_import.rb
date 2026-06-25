class MetadataImport < ApplicationRecord
  # Batch size guardrails (per the import contract).
  DEFAULT_BATCH_SIZE = 50
  MAX_BATCH_SIZE     = 100

  # Generated artifacts are cleaned up after this period.
  RETENTION_PERIOD = 30.days

  # Fixed columns offered by the downloadable starter template. The first
  # column is the asset path; the rest map directly onto asset metadata keys.
  TEMPLATE_COLUMNS = %w[
    asset_path
    title
    description
    copyright
    usage_terms
    alt_text
    tags
  ].freeze

  # Column appended to the results CSV describing the per-row outcome.
  STATUS_COLUMN  = "import_status".freeze
  MESSAGE_COLUMN = "import_message".freeze

  belongs_to :user

  # The uploaded CSV the user wants to import.
  has_one_attached :source_file
  # The generated results CSV (source rows + status/message columns).
  has_one_attached :result_file

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  validates :name, presence: true
  validates :batch_size, numericality: { greater_than: 0, less_than_or_equal_to: MAX_BATCH_SIZE }
  validates :field_separator, :multi_value_delimiter, :asset_path_column, presence: true

  scope :recent,      -> { order(created_at: :desc) }
  scope :expired,     -> { where(expires_at: ..Time.current) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  # Clamp the batch size into the allowed range.
  def normalized_batch_size
    [ [ batch_size.to_i, 1 ].max, MAX_BATCH_SIZE ].min
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end
end
