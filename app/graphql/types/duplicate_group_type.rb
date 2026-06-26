# frozen_string_literal: true

module Types
  # GraphQL type representing a {DuplicateGroup} — a set of assets that share
  # the same SHA-256 checksum.
  class DuplicateGroupType < Types::BaseObject
    description "A group of assets detected as duplicates based on SHA-256 checksum."

    field :id,                String,   null: false
    field :checksum,          String,   null: false,
          description: "The SHA-256 fingerprint shared by all member assets."
    field :status,            String,   null: false,
          description: "pending | resolved | dismissed"
    field :resolution_action, String,   null: true,
          description: "kept_all | deleted_duplicates (set when resolved)"
    field :total_count,       Integer,  null: false,
          description: "Number of member assets in this group."
    field :resolved_at,       GraphQL::Types::ISO8601DateTime, null: true
    field :resolved_by,       String,   null: true,
          description: "Email of the user who resolved the group."
    field :created_at,        GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at,        GraphQL::Types::ISO8601DateTime, null: false
    field :assets,            [ Types::DuplicateGroupAssetType ], null: false,
          description: "Member assets in this group."

    # Resolver for the +assets+ field — must be loaded via the REST serialiser
    # pattern to avoid N+1 queries.
    def assets
      object.duplicate_group_assets
            .includes(:asset)
            .order(is_original: :desc, created_at: :asc)
            .map do |dga|
              asset   = dga.asset
              version = asset&.active_version

              OpenStruct.new(
                asset_id:    dga.asset_id,
                title:       asset&.title,
                is_original: dga.is_original,
                status:      asset&.status,
                url:         nil, # URL helpers not wired into GraphQL context
                folder_id:   asset&.folder_id,
                folder_name: asset&.folder&.name || "Root / Uncategorized",
                folder_path: asset&.folder&.path,
                content_type: version&.properties&.dig("content_type"),
                file_size:   version&.properties&.dig("size"),
                uploaded_at: asset&.created_at&.iso8601,
                uploaded_by: asset&.user&.email,
              )
            end
    end

    # Resolved-by user email helper.
    def resolved_by
      object.resolved_by&.email
    end

    def self.authorized?(object, context)
      super && context[:current_user].present?
    end
  end
end
