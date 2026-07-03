# frozen_string_literal: true

require "rails_helper"

RSpec.describe AssetUrlHelper, type: :helper do
  let(:helper_class) do
    Class.new do
      include AssetUrlHelper
    end
  end

  let(:helper_obj) { helper_class.new }

  before do
    allow(helper_obj).to receive(:url_for) { |arg| "http://example.com/rails/active_storage/#{arg}" }
    allow(StorageBackend).to receive(:find_by).with(active: true).and_return(nil)
  end

  def build_asset(storage_path: nil, preview_path: nil, uuid: SecureRandom.uuid, with_version: true, asset_properties: nil)
    asset = build_stubbed(:asset, uuid: uuid)
    version = if with_version && (storage_path || preview_path)
                instance_double(
                  AssetVersion,
                  properties: { "storage_path" => storage_path, "preview_storage_path" => preview_path }.compact,
                  respond_to?: false,
                )
    else
                nil
    end
    allow(asset).to receive(:active_version).and_return(version)
    allow(asset).to receive(:properties).and_return(asset_properties.nil? ? { "storage_path" => storage_path, "preview_storage_path" => preview_path }.compact : asset_properties)
    asset
  end

  describe "#asset_url_for" do
    it "returns nil when no version or asset storage path is present" do
      asset = build_asset(storage_path: nil, with_version: false, asset_properties: nil)

      expect(helper_obj.asset_url_for(asset)).to be_nil
    end

    it "prefers an attached Active Storage file" do
      blob = double("blob")
      file = double("attached_file", attached?: true)
      active_version = instance_double(AssetVersion, file: file)
      asset = build_stubbed(:asset)
      allow(asset).to receive(:active_version).and_return(active_version)
      allow(asset).to receive(:properties).and_return({})

      expect(helper_obj.asset_url_for(asset)).to eq("http://example.com/rails/active_storage/#{file}")
    end

    it "bypasses local storage adapter URLs and falls back to the UUID route" do
      asset = build_asset(storage_path: "images/logo.png")
      backend = create(:storage_backend, active: true)
      local_adapter = StorageAdapters::LocalStorageAdapter.new("root" => "storage")
      allow(StorageBackend).to receive(:find_by).with(active: true).and_return(backend)
      allow(StorageManager).to receive(:adapter_for).with(backend).and_return(local_adapter)
      allow(local_adapter).to receive(:url)

      expect(helper_obj.asset_url_for(asset)).to eq("/api/v1/assets/local/#{asset.uuid}")
      expect(local_adapter).not_to have_received(:url)
    end

    it "returns the local UUID path in non-production environments" do
      asset = build_asset(storage_path: "some/file.jpg")

      expect(helper_obj.asset_url_for(asset)).to eq("/api/v1/assets/local/#{asset.uuid}")
    end

    it "returns CDN URLs in production" do
      asset = build_asset(storage_path: "images/logo.png")
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      stub_const("AssetUrlHelper::CDN_BASE_URL", -> { "https://cdn.example.com" })

      expect(helper_obj.asset_url_for(asset)).to eq("https://cdn.example.com/assets/#{asset.uuid}")
    end
  end

  describe "#asset_preview_url_for" do
    it "falls back to the normal asset URL when no preview path is present" do
      asset = build_asset(storage_path: "images/logo.png", preview_path: nil)
      allow(helper_obj).to receive(:asset_url_for).with(asset).and_return("/fallback")

      expect(helper_obj.asset_preview_url_for(asset)).to eq("/fallback")
    end

    it "returns a preview CDN URL in production when a preview path exists" do
      asset = build_asset(storage_path: "images/logo.png", preview_path: "previews/logo.png")
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      stub_const("AssetUrlHelper::CDN_BASE_URL", -> { "https://cdn.example.com" })

      expect(helper_obj.asset_preview_url_for(asset)).to eq("https://cdn.example.com/assets/#{asset.uuid}?variant=preview")
    end
  end

  describe "#asset_download_url_for" do
    it "delegates to asset_url_for with disposition: :download" do
      asset = build_asset(storage_path: "images/logo.png")
      expect(helper_obj).to receive(:asset_url_for).with(asset, disposition: :download)

      helper_obj.asset_download_url_for(asset)
    end
  end
end
