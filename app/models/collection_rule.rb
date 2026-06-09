class CollectionRule < ApplicationRecord
  belongs_to :collection

  # A rule can be responsible for mapping many assets over time
  has_many :collection_assets, dependent: :nullify

  validates :semantic_prompt, presence: true
  validates :similarity_threshold, numericality: { greater_than: 0.0, less_than_or_equal_to: 1.0 }

  # Auto-generate the vector embedding for the semantic_prompt before saving,
  # so the Sidekiq ingestion worker doesn't have to call the LLM to understand the rule.
  before_save :embed_semantic_prompt, if: :semantic_prompt_changed?

  private

  def embed_semantic_prompt
    # This reaches out to your Python FastAPI Gateway to convert the text prompt into a vector
    # e.g., self.properties['prompt_vector'] = ApiClient.embed(self.semantic_prompt)
  end
end