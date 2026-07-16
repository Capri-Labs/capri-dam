module Types
  # GraphQL type for a {CollectionRule} — smart-collection auto-routing config.
  class CollectionRuleType < Types::BaseObject
    graphql_name "CollectionRule"
    description "Auto-routing rule for a smart collection (semantic, metadata, or hybrid matching)"

    field :id, ID, null: false
    field :match_mode, String, null: false, description: "One of: semantic, metadata, hybrid"
    field :semantic_prompt, String, null: true
    field :similarity_threshold, Float, null: false
    field :metadata_filters, GraphQL::Types::JSON, null: true
    field :active, Boolean, null: false
  end
end
