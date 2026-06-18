class AssetVersion < ApplicationRecord
  belongs_to :asset
  belongs_to :created_by, class_name: 'User', optional: true

  #  The physical file is now attached HERE, making versions immutable
  has_one_attached :file

  validates :version_number, presence: true, uniqueness: { scope: :asset_id }

  # Automatically set this version as the active one upon creation if none exists
  after_create :set_as_active_if_first

  private

  def set_as_active_if_first
    if asset.active_version_id.nil?
      asset.update(active_version_id: self.id)
    end
  end
end