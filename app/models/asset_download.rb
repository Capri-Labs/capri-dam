class AssetDownload < ApplicationRecord
  # Generated ZIPs expire (and are cleaned up) after this period.
  RETENTION_PERIOD = 7.days

  belongs_to :user
  has_one_attached :zip_file

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  validates :name, presence: true

  scope :recent,      -> { order(created_at: :desc) }
  scope :expired,     -> { where(expires_at: ..Time.current) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :active_for,  ->(user) { where(user: user, status: %i[pending processing]) }

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  # Whole-percent completion for the Explorer's progress bar.
  def progress_percent
    return 100 if completed?
    return 0 if total_items.to_i.zero?

    ((processed_items.to_f / total_items) * 100).round.clamp(0, 99)
  end
end
