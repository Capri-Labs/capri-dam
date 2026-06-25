class Workflow < ApplicationRecord
  # Relationships
  has_many :workflow_steps, -> { order(position: :asc) }, dependent: :destroy

  # This allows saving steps directly via the Workflow Designer
  accepts_nested_attributes_for :workflow_steps, allow_destroy: true

  # Auditing & Ownership
  belongs_to :creator, class_name: "User", foreign_key: "created_by_id", optional: true
  belongs_to :last_modifier, class_name: "User", foreign_key: "updated_by_id", optional: true

  # Rails 7+ Enum Syntax
  enum :status, { inactive: 0, active: 1, draft: 2 }

  # Validations
  validates :name, presence: true
  validates :trigger_type, presence: true

  # Advanced logic: ensure at least one step exists for active workflows
  validate :must_have_steps, if: :active?

  private

  def must_have_steps
    if workflow_steps.empty? || workflow_steps.all?(&:marked_for_destruction?)
      errors.add(:base, "Active workflows must have at least one approval step")
    end
  end
end
