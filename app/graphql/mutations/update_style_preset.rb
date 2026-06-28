# frozen_string_literal: true

module Mutations
  # Updates a style preset (admin only).
  class UpdateStylePreset < BaseMutation
    description "Update an existing brand/style preset."

    argument :id,           ID,                   required: true
    argument :name,         String,               required: false
    argument :description,  String,               required: false
    argument :active,       Boolean,              required: false
    argument :style_params, GraphQL::Types::JSON, required: false

    field :style_preset, Types::StylePresetType, null: true
    field :errors,       [ String ],             null: false

    def resolve(**attrs)
      raise GraphQL::ExecutionError, "Administrator privileges required." unless context[:current_user]&.admin?

      id     = attrs.delete(:id)
      preset = StylePreset.find_by(id: id)
      return { style_preset: nil, errors: [ "Not found" ] } unless preset

      if preset.update(attrs.compact)
        { style_preset: preset, errors: [] }
      else
        { style_preset: nil, errors: preset.errors.full_messages }
      end
    end
  end
end
