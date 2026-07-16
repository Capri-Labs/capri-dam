class SmartCollectionRouterWorker
  include Sidekiq::Job

  # Configure Sidekiq strictly for 3 retries on the mailers queue.
  sidekiq_options queue: "smartai", retry: 3

  def perform(asset_id)
    asset = Asset.find_by(id: asset_id)
    return unless asset

    # Fetch all active rules. Unlike the original implementation, we no
    # longer bail out globally when the asset has no embedding yet —
    # metadata-only rules (see {CollectionRule#metadata_only?}) work purely
    # off `asset.properties` and must still be evaluated immediately, without
    # waiting on the (separate, async) AI embedding pipeline.
    rules = CollectionRule.where(active: true).includes(:collection)

    rules.each { |rule| evaluate_rule(asset, rule) }
  end

  private

  def evaluate_rule(asset, rule)
    # Skip if the collection is expired (Zero-Noise Operations)
    return if rule.collection.expires_at && rule.collection.expires_at < Time.current

    # 1. Evaluate Hard Guardrails (Metadata Filters) — applies to every mode
    return unless passes_metadata_filters?(asset, rule.metadata_filters)

    # 2. Pure metadata rules route immediately; no AI/embedding involved.
    if rule.metadata_only?
      map_asset_to_collection!(asset, rule)
      return
    end

    # 3. Semantic / hybrid modes additionally require a real vector
    # embedding on both sides of the comparison. The AI gateway integration
    # that populates `asset.asset_embedding` and `rule.prompt_vector` isn't
    # wired up in every environment, so we skip (rather than raise) when
    # either side is unavailable.
    asset_vector = asset.asset_embedding&.embedding
    return if asset_vector.blank? || rule.prompt_vector.blank?

    similarity = VectorCalculator.cosine_similarity(asset_vector, rule.prompt_vector)
    map_asset_to_collection!(asset, rule) if similarity >= rule.similarity_threshold
  end

  # Ensure every required key-value pair in the rule exists in the asset's
  # properties. Supports "any of" (OR) matching when either the configured
  # filter value or the asset's own property value is an array — e.g.
  # `{ "tags" => ["Q3 Campaign", "Social Media"] }` matches an asset tagged
  # with *either* value, and `{ "tags" => "Embargoed" }` matches an asset
  # whose `tags` array includes "Embargoed".
  def passes_metadata_filters?(asset, filters)
    return true if filters.blank?

    filters.all? do |key, required_value|
      values_match?(asset.properties[key.to_s], required_value)
    end
  end

  def values_match?(actual_value, required_value)
    (Array(actual_value) & Array(required_value)).any?
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

    Rails.logger.info("🤖 Routed Asset #{asset.id} to Collection #{rule.collection.name} via #{rule.match_mode} rule")
  end
end
