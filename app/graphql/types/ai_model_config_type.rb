# frozen_string_literal: true

module Types
  class AiModelConfigType < Types::BaseObject
    description "A registered AI model endpoint used by the Capri DAM gateway."

    field :id,                   ID,                              null: false
    field :name,                 String,                          null: false
    field :provider,             String,                          null: false
    field :model_id,             String,                          null: false
    field :capability,           String,                          null: false, description: "embedding | generation | vision | style_transfer | audio"
    field :enabled,              Boolean,                         null: false
    field :is_default,           Boolean,                         null: false
    field :config_params,        Types::JsonType,                 null: true
    field :health_status,        String,                          null: false, description: "healthy | degraded | unhealthy | unknown"
    field :health_latency_ms,    Integer,                         null: true
    field :last_health_check_at, GraphQL::Types::ISO8601DateTime, null: true
    field :error_message,        String,                          null: true
    field :metadata,             Types::JsonType,                 null: true
    field :created_at,           GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at,           GraphQL::Types::ISO8601DateTime, null: false

    def self.authorized?(object, context)
      super && context[:current_user]&.admin?
    end
  end
end
