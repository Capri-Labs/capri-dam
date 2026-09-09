# frozen_string_literal: true

require "rails_helper"

RSpec.describe Preservation::FormatRegistry do
  describe ".classify" do
    it "treats open, multiply-implemented formats as low risk" do
      expect(described_class.classify("image/jpeg")[:risk]).to eq(described_class::LOW)
      expect(described_class.classify("application/pdf")[:risk]).to eq(described_class::LOW)
    end

    it "flags formats whose runtime no longer exists" do
      expect(described_class.classify("application/x-shockwave-flash")[:risk]).to eq(described_class::HIGH)
      expect(described_class.classify("video/x-ms-wmv")[:risk]).to eq(described_class::HIGH)
    end

    it "treats single-vendor formats as worth an access copy" do
      expect(described_class.classify("image/vnd.adobe.photoshop")[:risk]).to eq(described_class::MEDIUM)
    end

    it "ignores charset parameters and casing" do
      expect(described_class.classify("TEXT/PLAIN; charset=utf-8")[:risk]).to eq(described_class::LOW)
    end

    it "calls an unassessed format unknown rather than safe" do
      expect(described_class.classify("application/x-made-up")).to eq(described_class::UNKNOWN)
      expect(described_class.classify(nil)).to eq(described_class::UNKNOWN)
      expect(described_class.classify("")).to eq(described_class::UNKNOWN)
    end
  end

  describe ".at_risk?" do
    it "is true only for formats already past their support horizon" do
      expect(described_class.at_risk?("application/x-director")).to be(true)
      expect(described_class.at_risk?("image/png")).to be(false)
      expect(described_class.at_risk?("image/heic")).to be(false)
    end
  end

  describe ".profile" do
    it "sorts the riskiest holdings to the top and totals by tier" do
      create(:asset, properties: { "content_type" => "image/png" })
      create(:asset, properties: { "content_type" => "image/png" })
      create(:asset, properties: { "content_type" => "video/x-flv" })

      profile = described_class.profile

      expect(profile[:formats].first[:content_type]).to eq("video/x-flv")
      expect(profile[:totals][:high_risk]).to eq(1)
      expect(profile[:totals][:low_risk]).to eq(2)
      expect(profile[:totals][:distinct_formats]).to eq(2)
    end

    it "excludes trashed assets from the obsolescence picture" do
      create(:asset, :trashed, properties: { "content_type" => "video/x-flv" })

      expect(described_class.profile[:totals][:assets]).to eq(0)
    end
  end
end
