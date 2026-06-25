class SmartCollectionRouterWorker
  include Sidekiq::Job

  # Configure Sidekiq strictly for 3 retries on the mailers queue.
  sidekiq_options queue: "smartai", retry: 3

  def perform(asset_id)
    asset = Asset.find_by(id: asset_id)
    return unless asset && asset.vector_embedding.present?

    # Fetch all active AI rules
    rules = CollectionRule.where(active: true).includes(:collection)

    rules.each do |rule|
      # Skip if the collection is expired (Zero-Noise Operations)
      next if rule.collection.expires_at && rule.collection.expires_at < Time.current

      # 1. Evaluate Hard Guardrails (Metadata Filters)
      next unless passes_metadata_filters?(asset, rule.metadata_filters)

      # 2. Evaluate Soft Guardrails (Semantic Vector Similarity)
      similarity = VectorCalculator.cosine_similarity(asset.vector_embedding, rule.prompt_vector)

      # 3. Route the Asset if it crosses the threshold
      if similarity >= rule.similarity_threshold
        map_asset_to_collection!(asset, rule)
      end
    end
  end

  private

  def passes_metadata_filters?(asset, filters)
    return true if filters.blank?

    # Ensure every required key-value pair in the rule exists in the asset's properties
    # E.g., filters = { "status" => "approved" }
    filters.all? do |key, required_value|
      asset.properties[key.to_s] == required_value
    end
  end

  def map_asset_to_collection!(asset, rule)
    # Using find_or_create_by ensures we don't crash on duplicate inserts
    CollectionAsset.find_or_create_by!(
      collection: rule.collection,
      asset: asset
    ) do |ca|
      # This block only executes if the record is newly created
      ca.collection_rule = rule
    end

    Rails.logger.info("🤖 AI Routed Asset #{asset.id} to Collection #{rule.collection.name}")
  end
end
