class Asset < ApplicationRecord
  belongs_to :user
  belongs_to :folder, optional: true

  has_one_attached :file

  validates :title, presence: true

  enum :status, { draft: 0, pending: 1, active: 2, rejected: 3 }

  scope :published, -> { where(status: :active) }

  after_initialize :set_property_defaults, if: :new_record?

  private

  def set_property_defaults
    # Using 'properties' to match your PG schema
    self.properties ||= {
      description: "",
      usage_terms: "Internal Use Only",
      alt_text: "",
      tags: []
    }
  end
end