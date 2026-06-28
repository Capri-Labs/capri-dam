# frozen_string_literal: true

module Types
  class AssetProvenanceRecordType < Types::BaseObject
    description "C2PA manifest and AI-provenance data for a single asset."

    field :id,                      ID,                              null: false
    field :asset_id,                String,                          null: false, description: "UUID of the owning asset"
    field :asset_uuid,              String,                          null: true
    field :asset_title,             String,                          null: true
    field :manifest_status,         String,                          null: false,
          description: "unchecked | verified | ai_generated | ai_modified | missing | invalid | signed | error"
    field :manifest_data,           Types::JsonType,                 null: true,  description: "Full parsed C2PA manifest payload"
    field :claim_generator,         String,                          null: true
    field :is_ai_modified,          Boolean,                         null: false
    field :ai_tools_used,           [ String ],                      null: false
    field :verified_at,             GraphQL::Types::ISO8601DateTime, null: true
    field :signed_at,               GraphQL::Types::ISO8601DateTime, null: true
    field :signer_name,             String,                          null: true
    field :signer_cert_fingerprint, String,                          null: true
    field :error_detail,            String,                          null: true
    field :created_at,              GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at,              GraphQL::Types::ISO8601DateTime, null: false

    def asset_uuid
      object.asset&.uuid
    end

    def asset_title
      object.asset&.title
    end

    def self.authorized?(_object, context)
      super && context[:current_user]&.admin?
    end
  end
end
