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
end
