class QuarantinedAsset < ApplicationRecord
  belongs_to :system_connector

  # Valid statuses: 'pending_review', 'resolved', 'discarded'
  validates :status, presence: true, inclusion: { in: %w[pending_review resolved discarded] }

  before_validation :set_default_status, on: :create

  private

  def set_default_status
    self.status ||= "pending_review"
  end
end
