# GraphQL query entry point — all read-only operations are defined here.
#
# == Available fields
#
# | Field | Return type | Description |
# |-------|-------------|-------------|
# | +assetDetail(uuid: ID!)+ | {Types::AssetType} | Fetch a single active asset by UUID |
# | +searchAssets(query, mode, metadataFilters)+ | [{Types::AssetType}] (connection) | Paginated asset search with optional facets |
# | +collections+ | [{Types::CollectionType}] | All active collections ordered by creation date |
# | +collection(slug: String!)+ | {Types::CollectionType} | Single collection by URL slug |
# | +imageProfiles+ | [{Types::ImageProfileType}] | All active image processing profiles |
# | +imageProfile(id: ID!)+ | {Types::ImageProfileType} | Single image profile by database ID |
#
# == Search behaviour (+searchAssets+)
#
# * +query+ — case-insensitive ILIKE title match.
# * +mode+  — +"images"+ (default) restricts results to +image/*+ content type;
#   pass any other value to search all asset types.
# * +metadataFilters+ — a free-form JSON key-value map applied as exact-match
#   JSONB property filters (e.g. +{ "dam:language_code": "en" }+).
#
# @see Types::AssetType
# @see Types::CollectionType
# @see Types::ImageProfileType
module Types
  class QueryType < Types::BaseObject
    description "The master query entry point for data recovery."

    # Returns a single active asset by its external UUID.
    #
    # @param uuid [String] the asset's public UUID (not the database integer ID)
    # @return [Types::AssetType, nil] +nil+ when not found or soft-deleted
    field :asset_detail, Types::AssetType, null: true do
      argument :uuid, String, required: true
    end

    # Paginated, filterable search over all active assets.
    #
    # @param query   [String, nil]  case-insensitive title substring
    # @param mode    [String]       +"images"+ (default) or any string to search all types
    # @param metadata_filters [Hash, nil] JSONB property key→value strict-match map
    # @return [GraphQL::Pagination::Connection<Types::AssetType>]
    field :search_assets, Types::AssetType.connection_type, null: false do
      argument :query,            String,         required: false
      argument :mode,             String,         required: false, default_value: 'images'
      argument :metadata_filters, Types::JsonType, required: false,
               description: "Key-value map for strict JSONB matching."
    end

    def asset_detail(uuid:)
      Asset.active.find_by(uuid: uuid)
    end

    def search_assets(query: nil, mode: 'images', metadata_filters: nil)
      scope = Asset.active
      scope = scope.where("title ILIKE ?", "%#{query}%") if query.present?
      scope = scope.where("properties->>'content_type' ILIKE 'image/%'") if mode == 'images'

      if metadata_filters.present?
        metadata_filters.each do |key, value|
          scope = scope.where("properties->>:key = :value", key: key, value: value)
        end
      end

      scope
    end

    # Returns all active, non-expired collections ordered newest-first.
    #
    # @return [Array<Types::CollectionType>]
    field :collections, [Types::CollectionType], null: false do
      description "Retrieve all active collections for the current workspace"
    end

    def collections
      Collection.active.order(created_at: :desc)
    end

    # Finds a single active collection by its URL-friendly slug.
    #
    # @param slug [String] the collection's unique slug
    # @return [Types::CollectionType, nil]
    field :collection, Types::CollectionType, null: true do
      description "Find a specific collection by its URL-friendly slug"
      argument :slug, String, required: true
    end

    def collection(slug:)
      Collection.active.find_by(slug: slug)
    end

    # Returns all active image processing profiles sorted alphabetically.
    #
    # @return [Array<Types::ImageProfileType>]
    field :image_profiles, [Types::ImageProfileType], null: false do
      description "List all active Image Processing Profiles"
    end

    def image_profiles
      ImageProfile.active.order(name: :asc)
    end

    # Finds an active image processing profile by its database ID.
    #
    # @param id [ID] the profile's database primary key
    # @return [Types::ImageProfileType, nil]
    field :image_profile, Types::ImageProfileType, null: true do
      description "Find an Image Processing Profile by ID"
      argument :id, ID, required: true
    end

    def image_profile(id:)
      ImageProfile.active.find_by(id: id)
    end
  end
end