# Auto-routing rule for a {Collection} (smart-collection engine).
#
# == Match modes
#
# A rule operates in one of three +match_mode+s, letting admins choose
# between AI-based semantic matching, simple metadata/tag matching, or both:
#
# | +match_mode+ | Requires             | Behavior |
# |--------------|-----------------------|----------|
# | +semantic+   | +semantic_prompt+     | Routes assets whose embedding's cosine similarity to the prompt's vector crosses +similarity_threshold+. (default — preserves original behavior) |
# | +metadata+   | +metadata_filters+    | Routes assets purely by matching +properties+ (e.g. tags, status) — no AI/embedding involved, works immediately on save. |
# | +hybrid+     | both                  | An asset must satisfy the metadata filters *and* cross the semantic similarity threshold. |
#
# == Metadata filter shape
#
# +metadata_filters+ is a hash of `{ "property_key" => value_or_array }`.
# Every key must match for the rule to pass (AND across keys); when the
# configured value (or the asset's own property) is an array, matching is
# "any of" (OR) — e.g. `{ "tags" => ["Q3 Campaign", "Social Media"] }`
# matches an asset tagged with *either* value. See
# {SmartCollectionRouterWorker#passes_metadata_filters?}.
#
# @see SmartCollectionRouterWorker
# @see Collection
class CollectionRule < ApplicationRecord
  MATCH_MODES = %w[semantic metadata hybrid].freeze

  belongs_to :collection

  # A rule can be responsible for mapping many assets over time
  has_many :collection_assets, dependent: :nullify

  validates :match_mode, inclusion: { in: MATCH_MODES }
  validates :semantic_prompt, presence: true, if: :requires_semantic_prompt?
  validates :metadata_filters, presence: true, if: :requires_metadata_filters?
  validates :similarity_threshold, numericality: { greater_than: 0.0, less_than_or_equal_to: 1.0 }

  # Auto-generate the vector embedding for the semantic_prompt before saving,
  # so the Sidekiq ingestion worker doesn't have to call the LLM to understand the rule.
  before_save :embed_semantic_prompt, if: -> { semantic_prompt_changed? && semantic_prompt.present? }

  # @return [Boolean] true when this rule routes purely by metadata/tags (no AI involved)
  def metadata_only?
    match_mode == "metadata"
  end

  # @return [Boolean] true when this rule routes purely by semantic similarity
  def semantic_only?
    match_mode == "semantic"
  end

  # @return [Boolean] true when both metadata AND semantic similarity must pass
  def hybrid?
    match_mode == "hybrid"
  end

  private

  # @api private
  def requires_semantic_prompt?
    match_mode.in?(%w[semantic hybrid])
  end

  # @api private
  def requires_metadata_filters?
    match_mode.in?(%w[metadata hybrid])
  end

  # @api private
  #
  # Reaches out to the AI Gateway to convert the text prompt into an
  # embedding vector so {SmartCollectionRouterWorker} can compare it against
  # asset embeddings without re-computing it on every single asset.
  # Not yet wired to a live gateway in this environment — mirrors other
  # AI-integration placeholders in this codebase (see
  # +Api::V1::CollectionsController#simulate_rule+ / +#cluster_map+).
  def embed_semantic_prompt
    # e.g., self.prompt_vector = AiGatewayClient.embed(self.semantic_prompt)
  end
end
