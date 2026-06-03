class AssetEmbedding < ApplicationRecord
  belongs_to :asset

  # Instructs the neighbor gem to treat this column as a high-dimensional vector
  has_neighbors :embedding

  validates :embedding, :model_name, presence: true
end