# frozen_string_literal: true

module Mutations
  # Updates an existing AI model config (admin only).
  class UpdateAiModelConfig < BaseMutation
    description "Update an AI model endpoint."

    argument :id,            ID,                           required: true
    argument :name,          String,                       required: false
    argument :provider,      String,                       required: false
    argument :model_id,      String,                       required: false
    argument :capability,    String,                       required: false
    argument :enabled,       Boolean,                      required: false
    argument :config_params, GraphQL::Types::JSON,         required: false
    argument :metadata,      GraphQL::Types::JSON,         required: false

    field :ai_model_config, Types::AiModelConfigType, null: true
    field :errors,          [ String ],               null: false

    def resolve(**attrs)
      raise GraphQL::ExecutionError, "Administrator privileges required." unless context[:current_user]&.admin?

      id     = attrs.delete(:id)
      config = AiModelConfig.find_by(id: id)
      return { ai_model_config: nil, errors: [ "Not found" ] } unless config

      if config.update(attrs.compact)
        { ai_model_config: config, errors: [] }
      else
        { ai_model_config: nil, errors: config.errors.full_messages }
      end
    end
  end
end
