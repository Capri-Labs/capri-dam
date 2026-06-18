module Types
  class AssetType < Types::BaseObject
    description "Represents a core cryptographic digital asset within the ecosystem."

    field :id, ID, null: false, complexity: 1
    field :uuid, String, null: false
    field :title, String, null: false, description: "The human-readable title of the asset."
    field :properties, Types::JsonType, null: true, description: "Raw JSONB custom attributes (Campaign, Region, etc)."
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false

    #  TEMPORARILY REMOVE OR COMMENT OUT THESE TWO LINES:
    # field :parent_folder, Types::FolderType, null: true, complexity: 5
    # field :active_workflows, [Types::WorkflowType], null: false, complexity: 10

    def self.authorized?(object, context)
      super && context[:current_user].present?
    end
  end
end