class Folder < ApplicationRecord
  # Ownership & Governance
  belongs_to :user

  # Hierarchical structure
  belongs_to :parent, class_name: 'Folder', optional: true
  has_many :children, class_name: 'Folder', foreign_key: 'parent_id', dependent: :destroy

  # Asset relationship
  has_many :assets, dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :user_id, presence: true

  # Ensure folder names are unique within the same parent folder
  validates :name, uniqueness: { scope: [:parent_id, :user_id], message: "already exists in this location" }

  before_validation :generate_slug, if: -> { name.present? && (name_changed? || slug.blank?) }

  # Helper for the React Breadcrumbs
  # Returns an array of hashes: [{id: 1, name: 'Root'}, {id: 5, name: 'Sub'}]
  def path_hierarchy
    path = []
    current = self
    while current
      path.unshift({ id: current.id, name: current.name, slug: current.slug })
      current = current.parent
    end
    path
  end

  private

  def generate_slug
    self.slug = name.parameterize
  end
end