module Types
  class CollectionType < Types::BaseObject
    graphql_name "Collection"
    description "A curated workspace of digital assets"

    field :id, ID, null: false
    field :uuid, String, null: false
    field :name, String, null: false
    field :slug, String, null: false
    field :description, String, null: true
    field :properties, GraphQL::Types::JSON, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false

    # Smart-collection auto-routing rule (nil for plain manual collections)
    field :collection_rule, Types::CollectionRuleType, null: true, description: "Auto-routing rule, if this is a smart collection"

    # Group-scoped access-governance policies (empty when the collection is
    # still on legacy allowed_groups/denied_groups access — see Collection#accessible_by?)
    field :policies, [ Types::CollectionPolicyType ], null: false, description: "Group-scoped access policies configured for this workspace"

    # The relational mapping: Returns the assets inside this collection
    field :assets, [ Types::AssetType ], null: false, description: "Assets attached to this collection"

    # Optimization: Use a custom resolver to prevent N+1 query issues if you load many collections at once
    def assets
      # In an enterprise production app, you would use GraphQL::Batch here or standard eager loading
      object.assets
    end

    def policies
      object.collection_policies
    end
  end
end
