# frozen_string_literal: true

module Mutations
  # Updates an existing {VideoProfile}.
  #
  # Pass +encoding_presets+ as a JSON-encoded array to replace ALL presets in
  # the profile. Each entry may include an +id+ to update an existing preset; omit
  # +id+ to create a new one. Include +"_destroy": true+ with an existing +id+ to
  # remove that preset.
  class UpdateVideoProfile < BaseMutation
    description "Update an existing Video Profile."

    argument :id,                            ID,      required: true
    argument :name,                          String,  required: false
    argument :description,                   String,  required: false
    argument :encode_for_adaptive_streaming, Boolean, required: false
    argument :smart_crop_ratios,             String,  required: false,
             description: "JSON-encoded array of { name, crop_ratio } objects"
    argument :encoding_presets,              String,  required: false,
             description: "JSON-encoded array of preset hashes (supports nested attributes)"

    field :video_profile, Types::VideoProfileType, null: true
    field :errors,        [String],                null: false

    def resolve(**args)
      unless context[:current_user]&.admin?
        return { video_profile: nil, errors: ['Administrator privileges required.'] }
      end

      profile = VideoProfile.active.find_by(id: args[:id])
      return { video_profile: nil, errors: ['Video profile not found.'] } unless profile

      attrs = {}
      attrs[:name]                          = args[:name]                          if args.key?(:name)
      attrs[:description]                   = args[:description]                   if args.key?(:description)
      attrs[:encode_for_adaptive_streaming] = args[:encode_for_adaptive_streaming] if args.key?(:encode_for_adaptive_streaming)

      if args.key?(:smart_crop_ratios)
        attrs[:smart_crop_ratios] = begin JSON.parse(args[:smart_crop_ratios]) rescue [] end
      end

      if args.key?(:encoding_presets)
        presets = begin JSON.parse(args[:encoding_presets]) rescue [] end
        attrs[:encoding_presets_attributes] = presets.map { |p| p.transform_keys(&:to_sym) }
      end

      if profile.update(attrs)
        { video_profile: profile, errors: [] }
      else
        { video_profile: nil, errors: profile.errors.full_messages }
      end
    end
  end
end

