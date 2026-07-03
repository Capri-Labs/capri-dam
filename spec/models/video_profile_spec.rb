require "rails_helper"

RSpec.describe VideoProfile, type: :model do
  describe "validations" do
    it "accepts blank smart crop ratios" do
      expect(build(:video_profile, smart_crop_ratios: [])).to be_valid
      expect(build(:video_profile, smart_crop_ratios: nil)).to be_valid
    end

    it "rejects smart crop ratios that are not arrays" do
      profile = build(:video_profile, smart_crop_ratios: { "name" => "16:9" })

      expect(profile).not_to be_valid
      expect(profile.errors[:smart_crop_ratios]).to include("must be an array")
    end

    it "rejects smart crop ratio entries without both name and crop_ratio" do
      profile = build(:video_profile, smart_crop_ratios: [ { "name" => "16:9" }, { "crop_ratio" => "4:3" } ])

      expect(profile).not_to be_valid
      expect(profile.errors[:smart_crop_ratios]).to include(
        "entry 1 must have 'name' and 'crop_ratio'",
        "entry 2 must have 'name' and 'crop_ratio'"
      )
    end
  end
end
