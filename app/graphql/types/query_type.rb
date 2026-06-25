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
# | +videoProfiles+ | [{Types::VideoProfileType}] | All active video processing profiles |
# | +videoProfile(id: ID!)+ | {Types::VideoProfileType} | Single video profile by database ID |
#
# == Search behaviour (+searchAssets+)
#
# * +query+ — case-insensitive ILIKE title match.
# * +mode+  — +"images"+ (default) restricts results to +image/*+ content type;
#   pass any other value to search all asset types.
# * +metadataFilters+ — a free-form JSON key-value map applied as exact-match
#   JSONB property filters (e.g. +{ "dam:language_code": "en" }+).
# * +sortBy+ — +name+ (default), +created_at+, +updated_at+, +size+, or +type+.
# * +sortDirection+ — +asc+ (default) or +desc+.
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
    # @param sort_by [String] field to order results by: +name+, +created_at+,
    #   +updated_at+, +size+, or +type+ (default +name+)
    # @param sort_direction [String] +asc+ (default) or +desc+
    # @return [GraphQL::Pagination::Connection<Types::AssetType>]
    field :search_assets, Types::AssetType.connection_type, null: false do
      argument :query,            String,         required: false
      argument :mode,             String,         required: false, default_value: 'images'
      argument :metadata_filters, Types::JsonType, required: false,
               description: "Key-value map for strict JSONB matching."
      argument :sort_by, String, required: false, default_value: 'name',
               description: "Sort field: name, created_at, updated_at, size, or type."
      argument :sort_direction, String, required: false, default_value: 'asc',
               description: "Sort direction: asc or desc."
    end

    def asset_detail(uuid:)
      Asset.active.find_by(uuid: uuid)
    end

    # Allowed sort fields mapped to SQL ordering expressions.
    ASSET_SORT_COLUMNS = {
      'name'       => 'title',
      'created_at' => 'created_at',
      'updated_at' => 'updated_at',
      # size & type live in the JSONB properties column
      'size'       => "(properties->>'size')::bigint",
      'type'       => "properties->>'content_type'"
    }.freeze

    def search_assets(query: nil, mode: 'images', metadata_filters: nil,
                      sort_by: 'name', sort_direction: 'asc')
      scope = Asset.active
      scope = scope.where("title ILIKE ?", "%#{query}%") if query.present?
      scope = scope.where("properties->>'content_type' ILIKE 'image/%'") if mode == 'images'

      if metadata_filters.present?
        metadata_filters.each do |key, value|
          scope = scope.where("properties->>:key = :value", key: key, value: value)
        end
      end

      column    = ASSET_SORT_COLUMNS[sort_by.to_s] || ASSET_SORT_COLUMNS['name']
      direction = sort_direction.to_s == 'desc' ? 'DESC' : 'ASC'
      scope.order(Arel.sql("#{column} #{direction} NULLS LAST"))
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

    # Returns all active video processing profiles sorted alphabetically.
    #
    # @return [Array<Types::VideoProfileType>]
    field :video_profiles, [Types::VideoProfileType], null: false do
      description "List all active Video Processing Profiles"
    end

    def video_profiles
      VideoProfile.active.order(name: :asc)
    end

    # Finds an active video processing profile by its database ID.
    #
    # @param id [ID] the profile's database primary key
    # @return [Types::VideoProfileType, nil]
    field :video_profile, Types::VideoProfileType, null: true do
      description "Find a Video Processing Profile by ID"
      argument :id, ID, required: true
    end

    def video_profile(id:)
      VideoProfile.active.find_by(id: id)
    end

    # -------------------------------------------------------------------------
    # Users (admin only)
    # -------------------------------------------------------------------------

    field :users, [Types::UserType], null: false do
      description "List all DAM users (admin only)"
    end

    def users
      return [] unless context[:current_user]&.admin?
      User.includes(:user_groups, :preference).order(created_at: :desc)
    end

    field :user, Types::UserType, null: true do
      description "Fetch a single DAM user by ID (admin only)"
      argument :id, ID, required: true
    end

    def user(id:)
      return nil unless context[:current_user]&.admin?
      User.find_by(id: id)
    end

    # -------------------------------------------------------------------------
    # User Groups (admin only)
    # -------------------------------------------------------------------------

    field :user_groups, [Types::UserGroupType], null: false do
      description "List all user groups (admin only)"
    end

    def user_groups
      return [] unless context[:current_user]&.admin?
      UserGroup.includes(:users, :child_groups).order(name: :asc)
    end

    field :user_group, Types::UserGroupType, null: true do
      description "Fetch a single user group by ID (admin only)"
      argument :id, ID, required: true
    end

    def user_group(id:)
      return nil unless context[:current_user]&.admin?
      UserGroup.find_by(id: id)
    end
  end
end