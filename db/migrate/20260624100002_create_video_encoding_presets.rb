# frozen_string_literal: true

class CreateVideoEncodingPresets < ActiveRecord::Migration[8.1]
  def change
    create_table :video_encoding_presets do |t|
      t.references :video_profile, null: false, foreign_key: true, index: true

      # Display
      t.string  :name, null: false

      # Video settings
      t.string  :video_format_codec,  null: false, default: 'h264',    comment: 'mp4 h.264 = h264'
      t.integer :width                                                   # null = auto
      t.integer :height,              null: false
      t.boolean :keep_aspect_ratio,   null: false, default: true
      t.integer :video_bitrate_kbps,  null: false
      t.integer :frame_rate_fps,      null: false, default: 30

      # Audio settings
      t.string  :audio_codec,         null: false, default: 'he_aac'
      t.integer :audio_bitrate_kbps,  null: false, default: 128

      # Advanced settings (shown on the "Advanced" tab)
      t.boolean :two_pass_encoding,   null: false, default: false
      t.boolean :constant_bitrate,    null: false, default: false
      t.string  :h264_profile                                            # baseline | main | high
      t.integer :audio_sampling_rate                                     # e.g. 44100, 48000

      # Custom advanced parameters (h264Level, keyframe, minBitrate, maxBitrate, audioBitrateCustom)
      t.jsonb   :advanced_params,     null: false, default: {}

      # Ordering within a profile
      t.integer :position, null: false, default: 0

      t.timestamps null: false
    end
  end
end

