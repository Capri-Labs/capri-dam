# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::StylePresetType do
  describe "#created_by" do
    it "returns nil when the preset has no creator" do
      preset = build_stubbed(:style_preset, created_by: nil)
      type = described_class.allocate
      allow(type).to receive(:object).and_return(preset)

      expect(type.created_by).to be_nil
    end
  end

  describe ".authorized?" do
    let(:preset) { build_stubbed(:style_preset) }

    it "allows admins" do
      expect(described_class.authorized?(preset, { current_user: build_stubbed(:user, :admin) })).to be(true)
    end

    it "returns nil for missing users" do
      expect(described_class.authorized?(preset, { current_user: nil })).to be_nil
    end
  end
end
