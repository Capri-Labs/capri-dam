class Asset < ApplicationRecord
  belongs_to :user
  belongs_to :folder, optional: true # Optional allows for "Root" level assets

  # Active Storage link (we'll set this up next)
  has_one_attached :file

  validates :name, presence: true

  # Metadata defaults (to prevent nil errors in the React Editor)
  after_initialize :set_metadata_defaults, if: :new_record?

  private

  def set_metadata_defaults
    self.metadata ||= {
      description: "",
      usage_terms: "Internal Use Only",
      alt_text: "",
      tags: []
    }
  end
end