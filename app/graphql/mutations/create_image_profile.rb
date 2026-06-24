# frozen_string_literal: true

module Mutations
  class CreateImageProfile < BaseMutation
    description "Create a new Image Processing Profile."

    argument :name,                    String,  required: true
    argument :crop_type,               String,  required: false, default_value: 'none'
    argument :responsive_crop_enabled, Boolean, required: false, default_value: false
    argument :responsive_crops,        String,  required: false, default_value: '[]',
             description: "JSON-encoded array of { name, width, height } objects"
    argument :swatch_enabled,          Boolean, required: false, default_value: false
    argument :swatch_width,            Integer, required: false, default_value: 100
    argument :swatch_height,           Integer, required: false, default_value: 100
    argument :unsharp_amount,          Float,   required: false, default_value: 1.75
    argument :unsharp_radius,          Float,   required: false, default_value: 0.2
    argument :unsharp_threshold,       Integer, required: false, default_value: 2

    field :image_profile, Types::ImageProfileType, null: true
    field :errors,        [String],                null: false

    def resolve(name:, crop_type:, responsive_crop_enabled:, responsive_crops:,
                swatch_enabled:, swatch_width:, swatch_height:,
                unsharp_amount:, unsharp_radius:, unsharp_threshold:)
      unless context[:current_user]&.admin?
        return { image_profile: nil, errors: ['Administrator privileges required.'] }
      end

      crops = begin JSON.parse(responsive_crops) rescue [] end

      profile = ImageProfile.new(
        name:                    name,
        crop_type:               crop_type,
        responsive_crop_enabled: responsive_crop_enabled,
        responsive_crops:        crops,
        swatch_enabled:          swatch_enabled,
        swatch_width:            swatch_width,
        swatch_height:           swatch_height,
        unsharp_mask:            { 'amount' => unsharp_amount, 'radius' => unsharp_radius, 'threshold' => unsharp_threshold }
      )

      if profile.save
        { image_profile: profile, errors: [] }
      else
        { image_profile: nil, errors: profile.errors.full_messages }
      end
    end
  end
end

