class AssetEmbedding < ApplicationRecord
  def self.instance_method_already_implemented?(method_name) = method_name.to_s == "model_name" ? false : super

  belongs_to :asset

  # Instructs the neighbor gem to treat this column as a high-dimensional vector
  has_neighbors :embedding

  after_commit :trigger_smart_routing, on: [ :create, :update ]

  validates :embedding, :model_name, presence: true

  private

  def trigger_smart_routing
    SmartCollectionRouterWorker.perform_async(self.asset_id)
  end
end
