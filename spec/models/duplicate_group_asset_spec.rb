require "rails_helper"

RSpec.describe DuplicateGroupAsset, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:duplicate_group_id) }
    it { is_expected.to validate_presence_of(:asset_id) }

    it "requires an asset to be unique within a duplicate group" do
      group = create(:duplicate_group)
      asset = create(:asset)
      create(:duplicate_group_asset, duplicate_group: group, asset: asset)

      duplicate = build(:duplicate_group_asset, duplicate_group: group, asset: asset)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:asset_id]).to include("is already a member of this duplicate group")
    end
  end

  describe ".cleanup_for_asset!" do
    it "removes every duplicate-group membership for the given asset" do
      asset = create(:asset)
      group_a = create(:duplicate_group, status: "pending")
      group_b = create(:duplicate_group, status: "pending")
      create(:duplicate_group_asset, duplicate_group: group_a, asset: asset)
      create(:duplicate_group_asset, duplicate_group: group_b, asset: asset)
      # Keep both groups above the 2-member threshold so we can isolate the
      # "removes memberships" behaviour from the "auto-resolve" behaviour.
      create_list(:duplicate_group_asset, 2, duplicate_group: group_a)
      create_list(:duplicate_group_asset, 2, duplicate_group: group_b)

      described_class.cleanup_for_asset!(asset)

      expect(described_class.where(asset_id: asset.id)).to be_empty
    end

    it "auto-resolves a group left with fewer than 2 members" do
      asset = create(:asset)
      group = create(:duplicate_group, status: "pending")
      create(:duplicate_group_asset, duplicate_group: group, asset: asset)
      create(:duplicate_group_asset, duplicate_group: group) # only 1 other member

      described_class.cleanup_for_asset!(asset)

      expect(group.reload.status).to eq("resolved")
    end

    it "does not resolve a group that still has 2+ members remaining" do
      asset = create(:asset)
      group = create(:duplicate_group, status: "pending")
      create(:duplicate_group_asset, duplicate_group: group, asset: asset)
      create_list(:duplicate_group_asset, 2, duplicate_group: group)

      described_class.cleanup_for_asset!(asset)

      expect(group.reload.status).to eq("pending")
    end

    it "is a no-op when the asset has no duplicate-group memberships" do
      asset = create(:asset)

      expect { described_class.cleanup_for_asset!(asset) }.not_to raise_error
    end

    it "allows the asset to be hard-destroyed afterwards without an FK violation" do
      asset = create(:asset)
      group = create(:duplicate_group, status: "pending")
      create(:duplicate_group_asset, duplicate_group: group, asset: asset)
      create(:duplicate_group_asset, duplicate_group: group)

      described_class.cleanup_for_asset!(asset)

      expect { asset.destroy! }.not_to raise_error
    end
  end
end
