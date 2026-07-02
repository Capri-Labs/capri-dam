require "rails_helper"

RSpec.describe EdgeMetadataSyncWorker, type: :worker do
  let(:asset) { create(:asset, properties: { "content_type" => "image/jpeg", "color_palette" => %w[#111111 #222222 #333333 #444444] }) }
  let(:version) { create(:asset_version, asset: asset, version_number: 7, properties: { "alt_text" => "Alt", "editor_state" => { "geometry" => { "focal_point" => { "x" => 10, "y" => 20 } } } }) }

  before { asset.update!(active_version: version) }

  it "returns early when the asset is missing" do
    expect(CdnManager).not_to receive(:sync_metadata)

    described_class.new.perform("missing")
  end

  it "syncs compact edge metadata to the CDN manager" do
    allow(CdnManager).to receive(:sync_metadata).and_return(true)

    described_class.new.perform(asset.uuid)

    expect(CdnManager).to have_received(:sync_metadata) do |uuid, payload_json|
      payload = JSON.parse(payload_json)
      expect(uuid).to eq(asset.uuid)
      expect(payload).to include("version" => 7, "alt_text" => "Alt", "dominant_colors" => %w[#111111 #222222 #333333])
      expect(payload["focal_point"]).to eq("x" => 10, "y" => 20)
    end
  end

  it "raises when the CDN manager reports failure" do
    allow(CdnManager).to receive(:sync_metadata).and_return(false)

    expect { described_class.new.perform(asset.uuid) }.to raise_error(RuntimeError, /Edge Metadata Sync Failed/)
  end
end
