# frozen_string_literal: true

module Types
  class StylePresetType < Types::BaseObject
    description "A brand/style profile used in AI-assisted generation and style-transfer tasks."

    field :id,           ID,                              null: false
    field :name,         String,                          null: false
    field :slug,         String,                          null: false
    field :description,  String,                          null: true
    field :active,       Boolean,                         null: false
    field :is_default,   Boolean,                         null: false
    field :style_params, Types::JsonType,                 null: true
    field :gateway_ref,  String,                          null: true
    field :synced_at,    GraphQL::Types::ISO8601DateTime, null: true
    field :stale,        Boolean,                         null: false
    field :created_by,   String,                          null: true
    field :created_at,   GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at,   GraphQL::Types::ISO8601DateTime, null: false

    def stale
      object.stale?
    end

    def created_by
      object.created_by&.email
    end

    def self.authorized?(object, context)
      super && context[:current_user]&.admin?
    end
  end
end
