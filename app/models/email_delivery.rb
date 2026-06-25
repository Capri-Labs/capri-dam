class EmailDelivery < ApplicationRecord
  belongs_to :email_template

  validates :recipient_email, presence: true
  validates :status, inclusion: { in: %w[pending sent failed] }
  validates :retry_count, numericality: { greater_than_or_equal_to: 0 }

  # Scopes for the Audit Dashboard
  scope :pending, -> { where(status: "pending") }
  scope :sent, -> { where(status: "sent") }
  scope :failed, -> { where(status: "failed") }

  # Helper to determine if we should give up
  def max_retries_reached?
    retry_count >= 3
  end

  def mark_as_sent!
    update(status: "sent", error_log: nil)
  end

  def mark_as_failed!(error_message)
    update(
      status: "failed",
      error_log: error_message
    )
  end
end
