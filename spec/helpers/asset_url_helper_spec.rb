# frozen_string_literal: true

require "rails_helper"

# AssetUrlHelper is a controller concern, but its logic is environment-driven
# and easily exercised through a plain object.  We extend an anonymous object
# so we get the module's behaviour without spinning up a full controller stack.
#
# Coverage:
#   - Returns nil when no storage path or ActiveStorage attachment is present
#   - Returns /api/v1/assets/local/:uuid in non-production environments
#   - Returns CDN URL in production using ENV["CDN_BASE_URL"]
#   - Falls back to the hard-coded CDN placeholder when ENV is absent
#   - asset_download_url_for delegates correctly
RSpec.describe AssetUrlHelper, type: :helper do
  let(:helper_obj) { Object.new.extend(described_class) }

  # Stub route helpers so specs don't need a full request context.
  before do
    allow(helper_obj).to receive(:url_for) { |arg| "http://example.com/rails/active_storage/#{arg}" }
  end

  def build_asset(storage_path: nil, uuid: SecureRandom.uuid, with_version: true)
    asset = build_stubbed(:asset, uuid: uuid)
    version = if with_version && storage_path
                instance_double(
                  AssetVersion,
                  properties: { "storage_path" => storage_path, "content_type" => "image/jpeg" },
                  respond_to?: false   # no ActiveStorage attachment
                )
    else
                nil
    end
    allow(asset).to receive(:active_version).and_return(version)
    allow(asset).to receive(:properties).and_return(
      storage_path ? { "storage_path" => storage_path } : {}
    )
    asset
  end

  # ─── nil-safety ────────────────────────────────────────────────────────────

  describe "#asset_url_for" do
    context "when there is no storage path and no ActiveStorage attachment" do
      it "returns nil" do
        asset = build_asset(storage_path: nil, with_version: false)
        allow(asset).to receive(:active_version).and_return(nil)
        expect(helper_obj.asset_url_for(asset)).to be_nil
      end
    end

    # ─── development environment (default for test suite) ────────────────────

    context "in the test/development environment" do
      it "returns the /api/v1/assets/local/:uuid path" do
        asset = build_asset(storage_path: "some/file.jpg")
        url   = helper_obj.asset_url_for(asset)
        expect(url).to eq("/api/v1/assets/local/#{asset.uuid}")
      end

      it "always uses the UUID regardless of the storage_path value" do
        asset = build_asset(storage_path: "../../etc/passwd")
        url   = helper_obj.asset_url_for(asset)
        expect(url).to eq("/api/v1/assets/local/#{asset.uuid}")
        expect(url).not_to include("passwd")
      end
    end

    # ─── production environment ───────────────────────────────────────────────

    context "in the production environment" do
      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production")) }

      it "returns the CDN URL using ENV['CDN_BASE_URL']" do
        asset = build_asset(storage_path: "images/logo.png")
        stub_const("AssetUrlHelper::CDN_BASE_URL", -> { "https://cdn.example.com" })
        url = helper_obj.asset_url_for(asset)
        expect(url).to eq("https://cdn.example.com/assets/#{asset.uuid}")
      end

      it "falls back to the hard-coded placeholder when ENV is absent" do
        asset = build_asset(storage_path: "images/logo.png")
        stub_const("AssetUrlHelper::CDN_BASE_URL", -> { "https://cdn.yourdam.com" })
        url = helper_obj.asset_url_for(asset)
        expect(url).to start_with("https://cdn.yourdam.com/assets/")
      end
    end

    # ─── staging environment ──────────────────────────────────────────────────

    context "in the staging environment" do
      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("staging")) }

      it "returns the CDN URL (not the local-serve path)" do
        asset = build_asset(storage_path: "images/banner.jpg")
        url   = helper_obj.asset_url_for(asset)
        expect(url).to include("/assets/#{asset.uuid}")
        expect(url).not_to include("/api/v1/assets/local/")
      end
    end
  end

  # ─── download variant ────────────────────────────────────────────────────────

  describe "#asset_download_url_for" do
    it "delegates to asset_url_for with disposition: :download" do
      asset = build_asset(storage_path: "images/logo.png")
      expect(helper_obj).to receive(:asset_url_for).with(asset, disposition: :download)
      helper_obj.asset_download_url_for(asset)
    end
  end
end
