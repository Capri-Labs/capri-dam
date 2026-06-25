class EmailTemplate < ApplicationRecord
  has_many :email_deliveries, dependent: :nullify

  validates :name, presence: true
  validates :event_trigger, presence: true, uniqueness: true
  validates :subject, presence: true
  validates :active, inclusion: { in: [ true, false ] }

  # Scopes for the UI
  scope :active, -> { where(active: true) }
end
