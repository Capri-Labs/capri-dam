# frozen_string_literal: true

# A single video rendition definition within a {VideoProfile}.
#
# Each preset maps directly to one FFmpeg/transcoder job and produces one MP4
# output file. Presets within an adaptive profile are bundled together as a
# multi-bitrate HLS or DASH manifest.
#
# == Basic Tab fields
#   video_format_codec, width, height, keep_aspect_ratio, video_bitrate_kbps,
#   frame_rate_fps, audio_codec, audio_bitrate_kbps
#
# == Advanced Tab fields
#   two_pass_encoding, constant_bitrate, h264_profile, audio_sampling_rate
#
# == Custom Parameters (+advanced_params+ JSONB)
#   h264Level        – H.264 level string, e.g. "3.0"
#   keyframe         – keyframe interval in frames (recommended: 60–300)
#   minBitrate       – minimum variable bitrate in Kbps
#   maxBitrate       – maximum variable bitrate in Kbps
#   audioBitrateCustom – force constant audio bitrate ("true"/"false")
#
# @see VideoProfile
class VideoEncodingPreset < ApplicationRecord
  VALID_CODECS      = %w[h264].freeze
  VALID_AUDIO_CODECS = %w[he_aac aac mp3].freeze
  VALID_H264_PROFILES = %w[baseline main high].freeze

  # ── Associations ─────────────────────────────────────────────────────────────
  belongs_to :video_profile, inverse_of: :encoding_presets

  # ── Validations ──────────────────────────────────────────────────────────────
  validates :name,               presence: true
  validates :video_format_codec, inclusion: { in: VALID_CODECS }
  validates :height,             numericality: { greater_than: 0, only_integer: true }
  validates :video_bitrate_kbps, numericality: { greater_than: 0, only_integer: true }
  validates :frame_rate_fps,     numericality: { greater_than: 0, only_integer: true }
  validates :audio_codec,        inclusion: { in: VALID_AUDIO_CODECS }
  validates :audio_bitrate_kbps, numericality: { greater_than: 0, only_integer: true }
  validates :width,              numericality: { greater_than: 0, only_integer: true }, allow_nil: true
  validates :h264_profile,       inclusion: { in: VALID_H264_PROFILES }, allow_nil: true
  validates :audio_sampling_rate, numericality: { greater_than: 0, only_integer: true }, allow_nil: true

  # ── Scopes ───────────────────────────────────────────────────────────────────
  default_scope { order(position: :asc, id: :asc) }

  # ── Helpers ───────────────────────────────────────────────────────────────────

  # Human-readable video size description.
  #
  # @return [String] e.g. "auto x 720" or "1280 x 720"
  def size_label
    "#{width.nil? ? "auto" : width} x #{height}"
  end

  # Returns the effective width for display — "auto" when nil.
  #
  # @return [String]
  def display_width
    width.nil? ? "auto" : width.to_s
  end
end
