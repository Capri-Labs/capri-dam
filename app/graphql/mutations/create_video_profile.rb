# frozen_string_literal: true

module Mutations
  # Creates a new {VideoProfile} with optional initial encoding presets.
  #
  # The +encoding_presets+ argument accepts a JSON-encoded array of preset
  # attribute hashes. Omit it to start with no presets (add them via update).
  class CreateVideoProfile < BaseMutation
    description "Create a new Video Profile with optional encoding presets."

    argument :name,                          String,  required: true
    argument :description,                   String,  required: false
    argument :encode_for_adaptive_streaming, Boolean, required: false, default_value: true
    argument :smart_crop_ratios,             String,  required: false, default_value: "[]",
             description: "JSON-encoded array of { name, crop_ratio } objects"
    argument :encoding_presets,              String,  required: false, default_value: "[]",
             description: "JSON-encoded array of encoding preset attribute hashes"

    field :video_profile, Types::VideoProfileType, null: true
    field :errors,        [ String ],                null: false

    def resolve(name:, description: nil, encode_for_adaptive_streaming:,
                smart_crop_ratios:, encoding_presets:)
      unless context[:current_user]&.admin?
        return { video_profile: nil, errors: [ "Administrator privileges required." ] }
      end

      crops   = begin JSON.parse(smart_crop_ratios)  rescue [] end
      presets = begin JSON.parse(encoding_presets)   rescue [] end

      profile = VideoProfile.new(
        name:                          name,
        description:                   description,
        encode_for_adaptive_streaming: encode_for_adaptive_streaming,
        smart_crop_ratios:             crops
      )

      presets.each { |attrs| profile.encoding_presets.build(attrs.symbolize_keys) }

      if profile.save
        { video_profile: profile, errors: [] }
      else
        { video_profile: nil, errors: profile.errors.full_messages }
      end
    end
  end
end
