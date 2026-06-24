# frozen_string_literal: true

module Types
  # GraphQL type for a {VideoProfile} configuration record.
  class VideoProfileType < Types::BaseObject
    description "A Video Processing Profile that defines one or more encoding presets for transcoding."

    field :id,                            ID,      null: false
    field :name,                          String,  null: false
    field :description,                   String,  null: true
    field :encode_for_adaptive_streaming, Boolean, null: false,
          description: "When true, all presets are validated for adaptive bitrate streaming compatibility"
    field :smart_crop_ratios,             Types::JsonType, null: true,
          description: "Array of { name, crop_ratio } objects for smart crop processing"
    field :adaptive_streaming_warnings,   [String], null: false,
          description: "Validation warnings about preset inconsistencies that block adaptive streaming"
    field :encoding_presets,              [Types::VideoEncodingPresetType], null: false
    field :folder_count,                  Integer, null: false
    field :created_at,                    GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at,                    GraphQL::Types::ISO8601DateTime, null: false

    def encoding_presets
      object.encoding_presets.to_a
    end

    def folder_count
      object.folder_assignments.size
    end

    def adaptive_streaming_warnings
      object.adaptive_streaming_warnings
    end

    def self.authorized?(object, context)
      super && context[:current_user].present?
    end
  end
end

