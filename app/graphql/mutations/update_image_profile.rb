# frozen_string_literal: true

module Mutations
  class UpdateImageProfile < BaseMutation
    description "Update an existing Image Processing Profile."

    argument :id,                      ID,      required: true
    argument :name,                    String,  required: false
    argument :crop_type,               String,  required: false
    argument :responsive_crop_enabled, Boolean, required: false
    argument :responsive_crops,        String,  required: false,
             description: "JSON-encoded array of { name, width, height } objects"
    argument :swatch_enabled,          Boolean, required: false
    argument :swatch_width,            Integer, required: false
    argument :swatch_height,           Integer, required: false
    argument :unsharp_amount,          Float,   required: false
    argument :unsharp_radius,          Float,   required: false
    argument :unsharp_threshold,       Integer, required: false

    field :image_profile, Types::ImageProfileType, null: true
    field :errors,        [String],                null: false

    def resolve(**args)
      unless context[:current_user]&.admin?
        return { image_profile: nil, errors: ['Administrator privileges required.'] }
      end

      profile = ImageProfile.active.find_by(id: args[:id])
      return { image_profile: nil, errors: ['Image profile not found.'] } unless profile

      attrs = {}
      attrs[:name]                    = args[:name]                    if args.key?(:name)
      attrs[:crop_type]               = args[:crop_type]               if args.key?(:crop_type)
      attrs[:responsive_crop_enabled] = args[:responsive_crop_enabled] if args.key?(:responsive_crop_enabled)
      attrs[:swatch_enabled]          = args[:swatch_enabled]          if args.key?(:swatch_enabled)
      attrs[:swatch_width]            = args[:swatch_width]            if args.key?(:swatch_width)
      attrs[:swatch_height]           = args[:swatch_height]           if args.key?(:swatch_height)

      if args.key?(:responsive_crops)
        attrs[:responsive_crops] = begin JSON.parse(args[:responsive_crops]) rescue [] end
      end

      if args.key?(:unsharp_amount) || args.key?(:unsharp_radius) || args.key?(:unsharp_threshold)
        current = profile.unsharp_mask || {}
        attrs[:unsharp_mask] = {
          'amount'    => args.fetch(:unsharp_amount,    current['amount']    || 1.75),
          'radius'    => args.fetch(:unsharp_radius,    current['radius']    || 0.2),
          'threshold' => args.fetch(:unsharp_threshold, current['threshold'] || 2)
        }
      end

      if profile.update(attrs)
        { image_profile: profile, errors: [] }
      else
        { image_profile: nil, errors: profile.errors.full_messages }
      end
    end
  end
end

