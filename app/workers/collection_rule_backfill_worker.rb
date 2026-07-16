# Re-evaluates every existing asset against a single {CollectionRule} —
# enqueued whenever an admin creates or updates a smart-collection rule via
# `Api::V1::CollectionsController#configure_rule`, so a newly (re)configured
# rule immediately sweeps the existing asset library instead of only
# affecting assets created/updated from that point forward.
#
# Delegates the actual matching logic to {SmartCollectionRouterWorker} (one
# job per asset) rather than duplicating it, so metadata-filter/semantic
# matching behavior can never drift between the "new asset" and "backfill"
# code paths.
class CollectionRuleBackfillWorker
  include Sidekiq::Job

  sidekiq_options queue: "smartai", retry: 3

  # @param rule_id [Integer] the {CollectionRule} to sweep the library for
  def perform(rule_id)
    rule = CollectionRule.find_by(id: rule_id)
    return unless rule&.active?

    Asset.active.in_batches(of: 500) do |batch|
      batch.pluck(:id).each { |asset_id| SmartCollectionRouterWorker.perform_async(asset_id) }
    end
  end
end
