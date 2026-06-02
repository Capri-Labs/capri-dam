class Collection < ApplicationRecord
  # Associations
  belongs_to :user # The owner/creator of the collection
  has_many :collection_assets, dependent: :destroy
  has_many :assets, through: :collection_assets

  # Validations
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :uuid, presence: true, uniqueness: true

  # Callbacks
  before_validation :generate_uuid, on: :create
  before_validation :generate_slug, on: :create

  # Scopes
  scope :active, -> { where(deleted_at: nil) }

  # AI Helper: Determine if this is a "Smart Collection" driven by an AI prompt
  def smart_collection?
    properties&.dig('ai_prompt').present?
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def generate_slug
    if name.present? && slug.blank?
      # Creates a clean, URL-safe string: "Black Friday 2026" -> "black-friday-2026"
      base_slug = name.parameterize
      self.slug = base_slug

      # Ensure uniqueness if there's a collision
      count = 1
      while Collection.exists?(slug: self.slug)
        self.slug = "#{base_slug}-#{count}"
        count += 1
      end
    end
  end
end