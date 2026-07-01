class EmailTemplate < ApplicationRecord
  CATEGORIES = %w[transactional notification mention announcement system].freeze

  belongs_to :created_by, class_name: "User", optional: true

  has_many :email_deliveries, dependent: :nullify
  has_many :inbox_messages, dependent: :nullify

  validates :name, presence: true
  validates :event_trigger, presence: true, uniqueness: true
  validates :subject, presence: true
  validates :active, inclusion: { in: [ true, false ] }
  validates :category, inclusion: { in: CATEGORIES }, allow_nil: true

  scope :active, -> { where(active: true) }
  scope :by_category, ->(category) { where(category: category) }
  scope :with_event, ->(event) { where(event_trigger: event) }

  def variable_names
    (variables || {}).keys
  end
end
