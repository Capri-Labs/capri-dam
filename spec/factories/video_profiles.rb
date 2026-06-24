# frozen_string_literal: true

FactoryBot.define do
  factory :video_encoding_preset do
    association :video_profile

    sequence(:name) { |n| "Preset #{n}" }
    video_format_codec  { 'h264' }
    width               { nil }   # auto
    height              { 360 }
    keep_aspect_ratio   { true }
    video_bitrate_kbps  { 730 }
    frame_rate_fps      { 30 }
    audio_codec         { 'he_aac' }
    audio_bitrate_kbps  { 128 }
    two_pass_encoding   { false }
    constant_bitrate    { false }
    h264_profile        { nil }
    audio_sampling_rate { nil }
    advanced_params     { {} }
    position            { 0 }

    trait :p360 do
      name               { '360p' }
      height             { 360 }
      video_bitrate_kbps { 730 }
      position           { 0 }
    end

    trait :p540 do
      name               { '540p' }
      height             { 540 }
      video_bitrate_kbps { 2000 }
      position           { 1 }
    end

    trait :p720 do
      name               { '720p' }
      height             { 720 }
      video_bitrate_kbps { 3000 }
      position           { 2 }
    end
  end

  factory :video_profile do
    sequence(:name) { |n| "Video Profile #{n}" }

    description                   { nil }
    encode_for_adaptive_streaming { true }
    smart_crop_ratios             { [] }
    deleted_at                    { nil }

    trait :with_adaptive_presets do
      after(:create) do |profile|
        VideoProfile.default_adaptive_presets.each do |attrs|
          create(:video_encoding_preset, attrs.merge(video_profile: profile))
        end
      end
    end

    trait :with_smart_crop do
      smart_crop_ratios do
        [
          { 'name' => '16:9', 'crop_ratio' => '16:9' },
          { 'name' => '4:3',  'crop_ratio' => '4:3' }
        ]
      end
    end

    trait :progressive do
      encode_for_adaptive_streaming { false }
    end

    trait :deleted do
      deleted_at { 1.day.ago }
    end

    trait :full do
      encode_for_adaptive_streaming { true }
      smart_crop_ratios do
        [{ 'name' => '16:9', 'crop_ratio' => '16:9' }]
      end
      after(:create) do |profile|
        VideoProfile.default_adaptive_presets.each do |attrs|
          create(:video_encoding_preset, attrs.merge(video_profile: profile))
        end
      end
    end
  end
end

