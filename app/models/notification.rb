class Notification < ApplicationRecord
  belongs_to :user

  # Scope to easily grab unread notifications
  scope :unread, -> { where(read_at: nil) }
end