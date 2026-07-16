module Mutations
  # GraphQL counterpart of +POST /api/v1/collections/:slug/rule+
  # (Api::V1::CollectionsController#configure_rule). Requires
  # {Collection#manageable_by?} (system admin, super-admin, group
  # collection-admin, or the workspace's own creator until an explicit
  # {CollectionPolicy} has been configured).
  class ConfigureCollectionRule < Mutations::BaseMutation
    description "Creates or updates a smart collection's auto-routing rule (semantic, metadata, or hybrid matching)."

    argument :collection_id, ID, required: true
    argument :match_mode, String, required: false, description: "One of: semantic, metadata, hybrid"
    argument :semantic_prompt, String, required: false
    argument :similarity_threshold, Float, required: false
    argument :metadata_filters, GraphQL::Types::JSON, required: false
    argument :active, Boolean, required: false

    field :collection, Types::CollectionType, null: true
    field :errors, [ String ], null: false

    def resolve(collection_id:, match_mode: nil, semantic_prompt: nil, similarity_threshold: nil, metadata_filters: nil, active: nil)
      user = context[:current_user]
      return { collection: nil, errors: [ "Authentication required." ] } unless user

      collection = Collection.active.find_by(id: collection_id)
      return { collection: nil, errors: [ "Collection not found" ] } unless collection

      unless collection.manageable_by?(user)
        return { collection: nil, errors: [ "You do not have administrative access to this workspace." ] }
      end

      collection.update!(collection_type: "smart") unless collection.smart?

      rule = collection.collection_rule || collection.build_collection_rule
      rule.match_mode = match_mode if match_mode.present?
      rule.semantic_prompt = semantic_prompt unless semantic_prompt.nil?
      rule.similarity_threshold = similarity_threshold || rule.similarity_threshold || 0.800
      rule.metadata_filters = metadata_filters unless metadata_filters.nil?
      rule.active = active.nil? ? (rule.active.nil? ? true : rule.active) : active

      if rule.save
        CollectionRuleBackfillWorker.perform_async(rule.id)
        { collection: collection.reload, errors: [] }
      else
        { collection: nil, errors: rule.errors.full_messages }
      end
    end
  end
end
