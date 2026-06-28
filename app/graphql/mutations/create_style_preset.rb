# frozen_string_literal: true

module Mutations
  # Creates a new style preset (admin only).
  class CreateStylePreset < BaseMutation
    description "Create a new brand/style preset."

    argument :name,         String,               required: true
    argument :description,  String,               required: false
    argument :active,       Boolean,              required: false, default_value: true
    argument :style_params, GraphQL::Types::JSON, required: false, default_value: {}

    field :style_preset, Types::StylePresetType, null: true
    field :errors,       [ String ],             null: false

    def resolve(name:, description: nil, active: true, style_params: {})
      raise GraphQL::ExecutionError, "Administrator privileges required." unless context[:current_user]&.admin?

      preset = StylePreset.new(name: name, description: description, active: active,
                                style_params: style_params, created_by: context[:current_user])
      if preset.save
        { style_preset: preset, errors: [] }
      else
        { style_preset: nil, errors: preset.errors.full_messages }
      end
    end
  end
end
