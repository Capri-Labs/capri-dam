class Folder < ApplicationRecord
  # The parent folder
  belongs_to :parent, class_name: 'Folder', optional: true

  # The subfolders
  has_many :children, class_name: 'Folder', foreign_key: 'parent_id', dependent: :destroy

  # The assets inside this folder
  has_many :assets, dependent: :destroy

  validates :name, presence: true

  # Automatically generate slug from name if you want
  before_validation :generate_slug, if: :name_changed?

  private

  def generate_slug
    self.slug = name.parameterize if name.present?
  end
end