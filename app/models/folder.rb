class Folder < ApplicationRecord
  # Ownership & Governance
  belongs_to :user

  # Ensure a UUID is generated if not provided by the database
  before_validation :ensure_uuid, on: :create

  # Hierarchical structure
  belongs_to :parent, class_name: 'Folder', optional: true
  has_many :children, class_name: 'Folder', foreign_key: 'parent_id', dependent: :destroy

  # Asset relationship
  has_many :assets, dependent: :destroy

  has_many :folder_policies, dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :user_id, presence: true

  # Ensure folder names are unique within the same parent folder
  validates :name, uniqueness: { scope: [:parent_id, :user_id], message: "already exists in this location" }

  before_validation :generate_slug, if: -> { name.present? && (name_changed? || slug.blank?) }

  include SoftDeletable

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

  # Quick helper to see which groups govern this specific folder
  def governing_groups
    UserGroup.joins(:folder_policies).where(folder_policies: { folder_id: id })
  end

  private

  def generate_slug
    self.slug = name.parameterize
  end

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end
end