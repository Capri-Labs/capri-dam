module Types
  class AssetType < Types::BaseObject
    description "Represents a core digital asset within the Capri DAM platform."

    field :id,             ID,                               null: false, complexity: 1
    field :uuid,           String,                           null: false,
          description: "Public UUID used in all external references."
    field :title,          String,                           null: false,
          description: "Human-readable display name."
    field :status,         String,                           null: false,
          description: "Processing / approval lifecycle status (draft, pending, ready, …)."
    field :url,            String,                           null: true,
          description: "Public URL to the active version of the asset. " \
                       "Returns the CDN URL in production or the authenticated " \
                       "local-serve endpoint (/api/v1/assets/local/:uuid) in development."
    field :version_number, Integer,                          null: true,
          description: "Active version number (1-based)."
    field :properties,     Types::JsonType,                  null: true,
          description: "Raw JSONB custom attributes (Campaign, Region, etc)."
    field :created_at,     GraphQL::Types::ISO8601DateTime,  null: false

    #  Temporarily disabled — re-enable once FolderType circular ref is resolved
    # field :parent_folder, Types::FolderType, null: true, complexity: 5
    # field :active_workflows, [Types::WorkflowType], null: false, complexity: 10

    def url
      helper = Object.new.extend(AssetUrlHelper)
      helper.asset_url_for(object)
    rescue StandardError
      nil
    end

    def version_number
      object.active_version&.version_number
    end

    def self.authorized?(object, context)
      super && context[:current_user].present?
    end
  end
end
