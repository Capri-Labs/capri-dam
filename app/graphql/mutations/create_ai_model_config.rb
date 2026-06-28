# frozen_string_literal: true

module Mutations
  # Creates a new AI model config record (admin only).
  class CreateAiModelConfig < BaseMutation
    description "Register a new AI model endpoint."

    argument :name,          String,                       required: true
    argument :provider,      String,                       required: true
    argument :model_id,      String,                       required: true
    argument :capability,    String,                       required: true
    argument :enabled,       Boolean,                      required: false, default_value: true
    argument :config_params, GraphQL::Types::JSON,         required: false, default_value: {}
    argument :metadata,      GraphQL::Types::JSON,         required: false, default_value: {}

    field :ai_model_config, Types::AiModelConfigType, null: true
    field :errors,          [ String ],               null: false

    def resolve(name:, provider:, model_id:, capability:, enabled: true, config_params: {}, metadata: {})
      raise GraphQL::ExecutionError, "Administrator privileges required." unless context[:current_user]&.admin?

      config = AiModelConfig.new(name: name, provider: provider, model_id: model_id,
                                  capability: capability, enabled: enabled,
                                  config_params: config_params, metadata: metadata)
      if config.save
        { ai_model_config: config, errors: [] }
      else
        { ai_model_config: nil, errors: config.errors.full_messages }
      end
    end
  end
end
