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
    field :preview_url,    String,                           null: true,
          description: "URL to a web-renderable preview of the asset. For formats " \
                       "browsers cannot display natively (PSD, TIFF, HEIC) this points " \
                       "at a generated PNG preview; otherwise it falls back to the asset URL."
    field :version_number, Integer,                          null: true,
          description: "Active version number (1-based)."
    field :properties,     Types::JsonType,                  null: true,
          description: "Raw JSONB custom attributes (Campaign, Region, etc)."
    field :created_at,     GraphQL::Types::ISO8601DateTime,  null: false
    field :usage_stats,    Types::JsonType,                  null: false,
          description: "App-observed usage counters ({ views:, downloads:, shares: }), " \
                       "backed by AssetUsageEvent rows. See Asset#usage_stats for what " \
                       "is (and isn't) captured — CDN-served hot-link traffic is excluded."
    field :published,      Boolean,                          null: false,
          description: "Whether this asset has been explicitly published " \
                       "(independent of the processing `status` lifecycle). " \
                       "See Mutations::PublishAsset / Mutations::UnpublishAsset."
    field :published_at,   GraphQL::Types::ISO8601DateTime,  null: true,
          description: "When this asset was last published; null when unpublished."

    field :entity_links, [ Types::AssetEntityType ], null: false, complexity: 5 do
      description "Entity links for this asset. Includes unconfirmed proposals by " \
                  "default; pass `assertedOnly: true` for links a person has stated " \
                  "or agreed with, which is what a policy decision should read."
      argument :relationship, String,  required: false,
               description: "Restrict to one relationship (depicts, shot_by, …)."
      argument :asserted_only, Boolean, required: false, default_value: false
    end

    def entity_links(relationship: nil, asserted_only: false)
      scope = object.asset_entities.includes(:entity)
      scope = scope.where(relationship: relationship) if relationship.present?
      scope = scope.asserted if asserted_only
      scope.order(:relationship)
    end

    #  Temporarily disabled — re-enable once FolderType circular ref is resolved
    # field :parent_folder, Types::FolderType, null: true, complexity: 5
    # field :active_workflows, [Types::WorkflowType], null: false, complexity: 10

    def url
      helper = Object.new.extend(AssetUrlHelper)
      helper.asset_url_for(object)
    rescue StandardError
      nil
    end

    def preview_url
      helper = Object.new.extend(AssetUrlHelper)
      helper.asset_preview_url_for(object)
    rescue StandardError
      nil
    end

    def version_number
      object.active_version&.version_number
    end

    def published
      object.published?
    end

    def self.authorized?(object, context)
      super && context[:current_user].present?
    end
  end
end
