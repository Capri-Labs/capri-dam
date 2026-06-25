# frozen_string_literal: true

# VideoProfile stores configuration for automatic video transcoding applied when
# the profile is assigned to a folder. Each profile contains one or more
# {VideoEncodingPreset} records that describe individual renditions.
#
# == Adaptive Bitrate Streaming
#
# When +encode_for_adaptive_streaming+ is +true+ the system validates that all
# presets in the profile share identical values for:
#   - video_format_codec
#   - audio_codec
#   - audio_bitrate_kbps
#   - keep_aspect_ratio
#   - two_pass_encoding
#   - constant_bitrate
#   - h264_profile
#   - audio_sampling_rate
#
# Mismatching values are flagged via {#adaptive_streaming_warnings} but do NOT
# prevent saving — the profile degrades to single-bitrate delivery.
#
# == Predefined Adaptive Presets
#
# The class method {.default_adaptive_presets} returns the recommended trio:
#   360p  (730 Kbps), 540p (2000 Kbps), 720p (3000 Kbps)  all at 30 fps / HE-AAC 128 Kbps
#
# == Smart Crop
#
# +smart_crop_ratios+ is a JSONB array of +{ name: String, crop_ratio: String }+
# objects, e.g. +[{ "name" => "16:9", "crop_ratio" => "16:9" }]+.
#
# @see VideoEncodingPreset
# @see VideoProfileFolderAssignment
class VideoProfile < ApplicationRecord
  # ── Associations ─────────────────────────────────────────────────────────────
  has_many :encoding_presets,
           class_name:  "VideoEncodingPreset",
           dependent:   :destroy,
           inverse_of:  :video_profile

  has_many :folder_assignments,
           class_name:  "VideoProfileFolderAssignment",
           dependent:   :destroy

  accepts_nested_attributes_for :encoding_presets,
                                allow_destroy: true

  # ── Validations ──────────────────────────────────────────────────────────────
  validates :name, presence: true
  validate  :smart_crop_ratios_structure

  # ── Scopes ───────────────────────────────────────────────────────────────────
  scope :active, -> { where(deleted_at: nil) }

  # ── Class methods ─────────────────────────────────────────────────────────────

  # Returns the three recommended adaptive-streaming encoding presets.
  #
  # @return [Array<Hash>] preset attribute hashes ready for +VideoEncodingPreset.new+
  def self.default_adaptive_presets
    [
      { name: "360p",  height: 360,  video_bitrate_kbps: 730,  frame_rate_fps: 30,
        audio_codec: "he_aac", audio_bitrate_kbps: 128, keep_aspect_ratio: true, position: 0 },
      { name: "540p",  height: 540,  video_bitrate_kbps: 2000, frame_rate_fps: 30,
        audio_codec: "he_aac", audio_bitrate_kbps: 128, keep_aspect_ratio: true, position: 1 },
      { name: "720p",  height: 720,  video_bitrate_kbps: 3000, frame_rate_fps: 30,
        audio_codec: "he_aac", audio_bitrate_kbps: 128, keep_aspect_ratio: true, position: 2 },
    ]
  end

  # ── Instance methods ─────────────────────────────────────────────────────────

  # Soft-deletes the profile by setting +deleted_at+ to the current time.
  #
  # @return [void]
  def soft_delete!
    update!(deleted_at: Time.current)
  end

  # Returns any fields across presets that would break adaptive bitrate streaming.
  # An empty array means all presets are consistent and adaptive streaming is possible.
  #
  # @return [Array<String>] human-readable warning messages
  def adaptive_streaming_warnings
    return [] unless encode_for_adaptive_streaming
    return [] if encoding_presets.size < 2

    warnings = []
    fields = %w[video_format_codec audio_codec audio_bitrate_kbps keep_aspect_ratio
                two_pass_encoding constant_bitrate h264_profile audio_sampling_rate]

    fields.each do |field|
      values = encoding_presets.map(&field.to_sym).uniq
      if values.size > 1
        warnings << "Presets have different '#{field}' values (#{values.join(", ")}). " \
                    "Adaptive bitrate streaming will not be possible."
      end
    end

    warnings
  end

  # Returns true when all presets are consistent enough to enable adaptive streaming.
  #
  # @return [Boolean]
  def adaptive_streaming_compatible?
    adaptive_streaming_warnings.empty?
  end

  # Determines whether a given MIME type is a video type applicable for this profile.
  #
  # @param mime [String] MIME type string, e.g. 'video/mp4'
  # @return [Boolean]
  def self.applicable_mime_type?(mime)
    mime.to_s.start_with?("video/")
  end

  private

  def smart_crop_ratios_structure
    return if smart_crop_ratios.blank?
    return errors.add(:smart_crop_ratios, "must be an array") unless smart_crop_ratios.is_a?(Array)

    smart_crop_ratios.each_with_index do |ratio, i|
      unless ratio.is_a?(Hash) && ratio["name"].present? && ratio["crop_ratio"].present?
        errors.add(:smart_crop_ratios, "entry #{i + 1} must have 'name' and 'crop_ratio'")
      end
    end
  end
end
