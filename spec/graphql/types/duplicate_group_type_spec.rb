require "rails_helper"

RSpec.describe Types::DuplicateGroupType do
  describe "#assets" do
    subject(:assets) { type_instance.assets }

    let(:type_instance) do
      described_class.allocate.tap do |instance|
        allow(instance).to receive(:object).and_return(group)
      end
    end

    let(:group) { instance_double(DuplicateGroup, duplicate_group_assets: association) }
    let(:association) { double("duplicate_group_assets") }
    let(:folder) { instance_double(Folder, name: "Campaigns", path: "/Campaigns") }
    let(:uploader) { instance_double(User, email: "uploader@example.com") }
    let(:version) { instance_double(AssetVersion, properties: { "content_type" => "image/png", "size" => 2048 }) }
    let(:full_asset) do
      instance_double(
        Asset,
        title: "Hero",
        status: "ready",
        folder_id: "12",
        folder: folder,
        active_version: version,
        created_at: Time.zone.parse("2026-07-01T10:00:00Z"),
        user: uploader
      )
    end
    let(:partial_asset) do
      instance_double(
        Asset,
        title: "Untimed",
        status: "processing",
        folder_id: nil,
        folder: nil,
        active_version: nil,
        created_at: nil,
        user: nil
      )
    end
    let(:rows) do
      [
        instance_double(DuplicateGroupAsset, asset_id: "missing-asset", is_original: false, asset: nil),
        instance_double(DuplicateGroupAsset, asset_id: "full-asset", is_original: true, asset: full_asset),
        instance_double(DuplicateGroupAsset, asset_id: "partial-asset", is_original: false, asset: partial_asset),
      ]
    end

    before do
      allow(association).to receive(:includes).with(:asset).and_return(association)
      allow(association).to receive(:order).with(is_original: :desc, created_at: :asc).and_return(rows)
    end

    it "maps nil, partial, and fully populated assets safely" do
      expect(assets.map(&:asset_id)).to eq(%w[missing-asset full-asset partial-asset])

      expect(assets.first).to have_attributes(
        title: nil,
        status: nil,
        folder_id: nil,
        folder_name: "Root / Uncategorized",
        folder_path: nil,
        content_type: nil,
        file_size: nil,
        uploaded_at: nil,
        uploaded_by: nil
      )

      expect(assets.second).to have_attributes(
        title: "Hero",
        status: "ready",
        folder_id: "12",
        folder_name: "Campaigns",
        folder_path: "/Campaigns",
        content_type: "image/png",
        file_size: 2048,
        uploaded_at: "2026-07-01T10:00:00Z",
        uploaded_by: "uploader@example.com"
      )

      expect(assets.third).to have_attributes(
        title: "Untimed",
        status: "processing",
        folder_name: "Root / Uncategorized",
        content_type: nil,
        file_size: nil,
        uploaded_at: nil,
        uploaded_by: nil
      )
    end
  end
end
