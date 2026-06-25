# frozen_string_literal: true

module Types
  # GraphQL type for a single {VideoEncodingPreset} within a {VideoProfile}.
  class VideoEncodingPresetType < Types::BaseObject
    description "A single video encoding rendition preset within a Video Profile."

    field :id,                  ID,      null: false
    field :name,                String,  null: false
    field :video_format_codec,  String,  null: false, description: "Codec identifier, e.g. 'h264'"
    field :width,               Integer, null: true,  description: "Width in pixels; nil means auto-scale"
    field :height,              Integer, null: false, description: "Height in pixels, e.g. 360, 540, 720"
    field :keep_aspect_ratio,   Boolean, null: false
    field :video_bitrate_kbps,  Integer, null: false, description: "Video bitrate in Kbps"
    field :frame_rate_fps,      Integer, null: false, description: "Frame rate in frames per second"
    field :audio_codec,         String,  null: false, description: "'he_aac', 'aac', or 'mp3'"
    field :audio_bitrate_kbps,  Integer, null: false, description: "Audio bitrate in Kbps"
    field :two_pass_encoding,   Boolean, null: false
    field :constant_bitrate,    Boolean, null: false
    field :h264_profile,        String,  null: true,  description: "'baseline', 'main', or 'high'"
    field :audio_sampling_rate, Integer, null: true,  description: "Audio sampling rate in Hz, e.g. 44100"
    field :advanced_params,     Types::JsonType, null: true, description: "Custom params: h264Level, keyframe, minBitrate, maxBitrate, audioBitrateCustom"
    field :position,            Integer, null: false
    field :size_label,          String,  null: false, description: "Human-readable size, e.g. 'auto x 720'"
    field :created_at,          GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at,          GraphQL::Types::ISO8601DateTime, null: false

    def size_label
      object.size_label
    end
  end
end
