class Asset < ApplicationRecord
  belongs_to :user
  belongs_to :folder, optional: true

  # 🚨 REMOVED: after_commit :trigger_upload_workflows, on: :create

  has_many :workflow_instances, dependent: :destroy
  has_one_attached :file

  validates :title, presence: true

  enum :status, {
    draft: 0,
    pending: 1,
    processing: 2,
    ready: 3,
    in_review: 4,
    approved: 5,
    rejected: 6,
    failed: 7
  }

  scope :published, -> { where(status: :active) }

  after_initialize :set_property_defaults, if: :new_record?

  include SoftDeletable

  private

  def set_property_defaults
    self.properties ||= {
      description: "",
      usage_terms: "Internal Use Only",
      alt_text: "",
      tags: []
    }
  end
end