class CollectionAsset < ApplicationRecord
  # Associations
  belongs_to :collection
  belongs_to :asset
  belongs_to :user, optional: true # Tracks WHO manually added the asset
  belongs_to :collection_rule, optional: true # Tracks WHICH AI rule added the asset

  # Validations
  validates :asset_id, uniqueness: {
    scope: :collection_id,
    message: "is already in this collection"
  }

  # Callbacks
  before_create :assign_default_position

  def manually_curated?
    collection_rule_id.nil? || pinned?
  end

  def pinned
    self.read_attribute(:pinned)
  end

  private

  # If a marketing user drags-and-drops assets, the position updates.
  # By default, we put the newest added asset at the end of the list.
  def assign_default_position
    return if position.present? && position > 0
    max_position = CollectionAsset.where(collection_id: collection_id).maximum(:position) || 0
    self.position = max_position + 1
  end
end