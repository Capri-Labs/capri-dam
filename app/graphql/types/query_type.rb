module Types
  class QueryType < Types::BaseObject
    description "The master query entry point for data recovery."

    field :asset_detail, Types::AssetType, null: true do
      argument :uuid, String, required: true
    end

    field :search_assets, Types::AssetType.connection_type, null: false do
      argument :query, String, required: false
      argument :mode, String, required: false, default_value: 'images'
      argument :metadata_filters, Types::JsonType, required: false, description: "Key-value map for strict JSONB matching."
    end

    def asset_detail(uuid:)
      Asset.active.find_by(uuid: uuid)
    end

    def search_assets(query: nil, mode: 'images', metadata_filters: nil)
      scope = Asset.active

      # Apply text matching
      scope = scope.where("title ILIKE ?", "%#{query}%") if query.present?

      # Apply discrete context filtering
      scope = scope.where("properties->>'content_type' ILIKE 'image/%'") if mode == 'images'

      # Dynamically loop through granular custom facets if supplied
      if metadata_filters.present?
        metadata_filters.each do |key, value|
          scope = scope.where("properties->>:key = :value", key: key, value: value)
        end
      end

      scope
    end

    # 1. Fetch all collections
    field :collections, [Types::CollectionType], null: false do
      description "Retrieve all active collections for the current workspace"
    end

    def collections
      # Assuming you have a current_user context. If not, just return Collection.active
      Collection.active.order(created_at: :desc)
    end

    # 2. Fetch a specific collection by slug (for the Detail View)
    field :collection, Types::CollectionType, null: true do
      description "Find a specific collection by its URL-friendly slug"
      argument :slug, String, required: true
    end

    def collection(slug:)
      Collection.active.find_by(slug: slug)
    end

    # Image Profiles
    field :image_profiles, [Types::ImageProfileType], null: false do
      description "List all active Image Processing Profiles"
    end

    def image_profiles
      ImageProfile.active.order(name: :asc)
    end

    field :image_profile, Types::ImageProfileType, null: true do
      description "Find an Image Processing Profile by ID"
      argument :id, ID, required: true
    end

    def image_profile(id:)
      ImageProfile.active.find_by(id: id)
    end
  end
end