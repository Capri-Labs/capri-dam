# frozen_string_literal: true

module Types
  # GraphQL type representing a single member asset within a {DuplicateGroup}.
  class DuplicateGroupAssetType < Types::BaseObject
    description "A member asset within a duplicate group."

    field :asset_id,     String,  null: false
    field :title,        String,  null: true
    field :is_original,  Boolean, null: false,
          description: "True for the oldest (original) asset in the group."
    field :status,       String,  null: true
    field :url,          String,  null: true, description: "Public or storage URL."
    field :folder_id,    String,  null: true
    field :folder_name,  String,  null: true
    field :folder_path,  String,  null: true
    field :content_type, String,  null: true
    field :file_size,    GraphQL::Types::BigInt, null: true
    field :uploaded_at,  String,  null: true
    field :uploaded_by,  String,  null: true
  end
end
