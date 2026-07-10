# frozen_string_literal: true

require "rails_helper"

RSpec.describe VideoEncodingPreset, type: :model do
  describe "#size_label" do
    it "uses auto when width is nil" do
      preset = build(:video_encoding_preset, width: nil, height: 720)

      expect(preset.size_label).to eq("auto x 720")
    end

    it "uses the explicit width when present" do
      preset = build(:video_encoding_preset, width: 1280, height: 720)

      expect(preset.size_label).to eq("1280 x 720")
    end
  end

  describe "#display_width" do
    it "returns auto for nil widths" do
      preset = build(:video_encoding_preset, width: nil)

      expect(preset.display_width).to eq("auto")
    end

    it "returns the width as a string when present" do
      preset = build(:video_encoding_preset, width: 1920)

      expect(preset.display_width).to eq("1920")
    end
  end

  describe "video_format_codec validation" do
    it "accepts h264, av1, and vp9" do
      %w[h264 av1 vp9].each do |codec|
        preset = build(:video_encoding_preset, video_format_codec: codec)

        expect(preset).to be_valid
      end
    end

    it "rejects an unsupported codec" do
      preset = build(:video_encoding_preset, video_format_codec: "hevc")

      expect(preset).not_to be_valid
      expect(preset.errors[:video_format_codec]).to be_present
    end
  end

  describe "audio_codec validation" do
    it "accepts opus (used for AV1/WebM renditions) alongside the existing codecs" do
      preset = build(:video_encoding_preset, audio_codec: "opus")

      expect(preset).to be_valid
    end
  end
end
