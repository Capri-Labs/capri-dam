# frozen_string_literal: true

module Types
  class ImageProfileType < Types::BaseObject
    description "An Image Processing Profile that defines sharpening, cropping, and swatch generation settings."

    field :id,                      ID,                    null: false
    field :name,                    String,                null: false
    field :unsharp_mask,            Types::JsonType,       null: true,  description: "Unsharp mask settings: { amount, radius, threshold }"
    field :crop_type,               String,                null: false, description: "'none' or 'smart_crop'"
    field :responsive_crop_enabled, Boolean,               null: false
    field :responsive_crops,        Types::JsonType,       null: true,  description: "Array of { name, width, height } responsive crop breakpoints"
    field :swatch_enabled,          Boolean,               null: false
    field :swatch_width,            Integer,               null: true
    field :swatch_height,           Integer,               null: true
    field :folder_count,            Integer,               null: false
    field :created_at,              GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at,              GraphQL::Types::ISO8601DateTime, null: false

    def folder_count
      object.folder_assignments.size
    end

    def self.authorized?(object, context)
      super && context[:current_user].present?
    end
  end
end

