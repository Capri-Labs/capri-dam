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
                  id: SecureRandom.uuid,
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

    it "falls back to an attached Active Storage file when no storage_path is present" do
      blob = double("blob")
      file = double("attached_file", attached?: true)
      active_version = instance_double(AssetVersion, file: file, properties: {})
      asset = build_stubbed(:asset)
      allow(asset).to receive(:active_version).and_return(active_version)
      allow(asset).to receive(:properties).and_return({})

      expect(helper_obj.asset_url_for(asset)).to eq("http://example.com/rails/active_storage/#{file}")
    end

    it "prefers storage_path over an attached Active Storage file" do
      # Regression test: active_storage_attachments.record_id is a bigint
      # column but Asset/AssetVersion use uuid primary keys, so every
      # attachment is persisted with record_id: 0. `file.attached?` can
      # therefore spuriously return true for an unrelated version's blob.
      # storage_path — written authoritatively by the upload/migration
      # pipeline — must win to avoid serving the wrong image.
      file = double("attached_file", attached?: true)
      active_version = instance_double(
        AssetVersion,
        id: SecureRandom.uuid,
        file: file,
        properties: { "storage_path" => "images/real-file.jpg" },
      )
      asset = build_stubbed(:asset)
      allow(asset).to receive(:active_version).and_return(active_version)
      allow(asset).to receive(:properties).and_return({})

      expect(helper_obj.asset_url_for(asset)).to eq("/api/v1/assets/local/#{asset.uuid}?version_id=#{active_version.id}")
      expect(file).not_to have_received(:attached?)
    end

    it "bypasses local storage adapter URLs and falls back to the UUID route" do
      asset = build_asset(storage_path: "images/logo.png")
      version = asset.active_version
      backend = create(:storage_backend, active: true)
      local_adapter = StorageAdapters::LocalStorageAdapter.new("root" => "storage")
      allow(StorageBackend).to receive(:find_by).with(active: true).and_return(backend)
      allow(StorageManager).to receive(:adapter_for).with(backend).and_return(local_adapter)
      allow(local_adapter).to receive(:url)

      expect(helper_obj.asset_url_for(asset)).to eq("/api/v1/assets/local/#{asset.uuid}?version_id=#{version.id}")
      expect(local_adapter).not_to have_received(:url)
    end

    it "returns the local UUID path in non-production environments" do
      asset = build_asset(storage_path: "some/file.jpg")
      version = asset.active_version

      expect(helper_obj.asset_url_for(asset)).to eq("/api/v1/assets/local/#{asset.uuid}?version_id=#{version.id}")
    end

    # Regression test: a prior version of this method only bypassed the local
    # storage adapter's raw `url(path)` (which embeds the raw filesystem
    # storage path, not a UUID) when no *explicit* `version:` was passed —
    # but the Version History diff/compare view (Api::V1::AssetsController
    # #versions) calls `asset_preview_url_for(@asset, version: v)` for every
    # historical version, so every version-scoped preview URL for local
    # storage leaked the raw file path and always 404'd via #serve_local
    # (which resolves by asset UUID, never by raw path).
    it "bypasses the local storage adapter even when an explicit version is passed" do
      asset = build_asset(storage_path: "images/logo.png")
      version = asset.active_version
      backend = create(:storage_backend, active: true)
      local_adapter = StorageAdapters::LocalStorageAdapter.new("root" => "storage")
      allow(StorageBackend).to receive(:find_by).with(active: true).and_return(backend)
      allow(StorageManager).to receive(:adapter_for).with(backend).and_return(local_adapter)
      allow(local_adapter).to receive(:url)

      expect(helper_obj.asset_url_for(asset, version: version)).to eq("/api/v1/assets/local/#{asset.uuid}?version_id=#{version.id}")
      expect(local_adapter).not_to have_received(:url)
    end

    it "memoizes the StorageBackend lookup across multiple calls on the same helper instance" do
      # Regression/perf test: FoldersController#show previously called
      # `StorageBackend.find_by(active: true)` once *per asset* when
      # formatting a folder listing (via asset_url_for), adding thousands of
      # extra DB round-trips for folders with 1,000-3,000+ assets. It must
      # now be looked up at most once per request (helper instance).
      asset1 = build_asset(storage_path: "images/one.jpg")
      asset2 = build_asset(storage_path: "images/two.jpg")
      backend = create(:storage_backend, active: true)
      allow(StorageBackend).to receive(:find_by).with(active: true).and_return(backend)
      allow(StorageManager).to receive(:adapter_for).with(backend).and_return(nil)

      helper_obj.asset_url_for(asset1)
      helper_obj.asset_url_for(asset2)
      helper_obj.asset_url_for(asset1)

      expect(StorageBackend).to have_received(:find_by).with(active: true).once
    end

    it "returns CDN URLs in production" do
      asset = build_asset(storage_path: "images/logo.png")
      version = asset.active_version
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      stub_const("AssetUrlHelper::CDN_BASE_URL", -> { "https://cdn.example.com" })

      expect(helper_obj.asset_url_for(asset)).to eq("https://cdn.example.com/assets/#{asset.uuid}?version_id=#{version.id}")
    end
  end

  describe "#asset_preview_url_for" do
    it "falls back to the normal asset URL when no preview path is present" do
      asset = build_asset(storage_path: "images/logo.png", preview_path: nil)
      allow(helper_obj).to receive(:asset_url_for).with(asset, version: nil).and_return("/fallback")

      expect(helper_obj.asset_preview_url_for(asset)).to eq("/fallback")
    end

    it "returns a preview CDN URL in production when a preview path exists" do
      asset = build_asset(storage_path: "images/logo.png", preview_path: "previews/logo.png")
      version = asset.active_version
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      stub_const("AssetUrlHelper::CDN_BASE_URL", -> { "https://cdn.example.com" })

      expect(helper_obj.asset_preview_url_for(asset)).to eq("https://cdn.example.com/assets/#{asset.uuid}?variant=preview&version_id=#{version.id}")
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
