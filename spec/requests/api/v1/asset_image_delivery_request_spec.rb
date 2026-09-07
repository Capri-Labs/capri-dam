# frozen_string_literal: true

require "rails_helper"

# End-to-end coverage for request-time image format negotiation on the local
# delivery endpoint (Api::V1::AssetsController#serve_local).
RSpec.describe "Api::V1::Assets image delivery", type: :request do
  let(:user) { create(:user, :admin) }
  let(:dam_dir) { Rails.root.join("storage/dam/image_delivery_spec") }
  let(:relative_path) { "image_delivery_spec/hero.jpg" }

  # A browser that accepts everything modern, as Chrome does.
  let(:modern_accept) { { "Accept" => "image/avif,image/webp,image/apng,image/*,*/*;q=0.8" } }

  before do
    sign_in user
    allow(AssetProcessorWorker).to receive(:perform_async) if defined?(AssetProcessorWorker)
    allow(CdnInvalidationWorker).to receive(:perform_async) if defined?(CdnInvalidationWorker)

    FileUtils.mkdir_p(dam_dir)
    system("magick", "-size", "900x600", "plasma:fractal", "-quality", "92",
           dam_dir.join("hero.jpg").to_s, out: File::NULL, err: File::NULL)
  end

  after do
    FileUtils.rm_rf(dam_dir)
    FileUtils.rm_rf(Rails.root.join(ImageDelivery::Derivative::CACHE_ROOT))
  end

  def enable_formats(*formats)
    create(:cdn_configuration, provider: "fastly", is_active: true,
                               settings: { "image_optimizer_formats" => formats })
  end

  def image_asset(content_type: "image/jpeg", path: relative_path)
    properties = {
      "original_filename" => "hero.jpg",
      "content_type" => content_type,
      "storage_path" => path,
      "size" => 1024,
    }
    asset = create(:asset, user: user, title: "Hero", status: :ready, properties: properties)
    version = create(:asset_version, asset: asset, version_number: 1,
                                     created_by: user, properties: properties)
    asset.update!(active_version: version)
    asset
  end

  describe "with AVIF enabled" do
    before { enable_formats("avif", "webp") }

    it "serves AVIF bytes to a browser that accepts it" do
      asset = image_asset

      get "/api/v1/assets/local/#{asset.uuid}", headers: modern_accept

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/avif")
      # Not just the header: the body must really be an AVIF container.
      expect(response.body[4, 8]).to eq("ftypavif")
    end

    it "sends Vary: Accept so a shared cache cannot serve AVIF to a client that cannot decode it" do
      asset = image_asset

      get "/api/v1/assets/local/#{asset.uuid}", headers: modern_accept

      expect(response.headers["Vary"]).to include("Accept")
    end

    it "sends Vary: Accept even when it serves the original untouched" do
      asset = image_asset

      get "/api/v1/assets/local/#{asset.uuid}", headers: { "Accept" => "image/png,*/*" }

      expect(response.media_type).to eq("image/jpeg")
      expect(response.headers["Vary"]).to include("Accept")
    end

    it "serves the original to a browser that accepts neither format" do
      asset = image_asset

      get "/api/v1/assets/local/#{asset.uuid}", headers: { "Accept" => "image/png,image/*,*/*;q=0.8" }

      expect(response.media_type).to eq("image/jpeg")
    end

    it "falls back to WebP for a client that accepts only WebP" do
      asset = image_asset

      get "/api/v1/assets/local/#{asset.uuid}",
          headers: { "Accept" => "image/webp,image/apng,image/*,*/*;q=0.8" }

      expect(response.media_type).to eq("image/webp")
      expect(response.body[8, 4]).to eq("WEBP")
    end

    it "delivers fewer bytes than the original" do
      asset = image_asset
      original_bytes = File.size(dam_dir.join("hero.jpg"))

      get "/api/v1/assets/local/#{asset.uuid}", headers: modern_accept

      expect(response.body.bytesize).to be < original_bytes
    end

    it "gives each format its own ETag" do
      asset = image_asset

      get "/api/v1/assets/local/#{asset.uuid}", headers: modern_accept
      avif_etag = response.headers["ETag"]

      get "/api/v1/assets/local/#{asset.uuid}", headers: { "Accept" => "image/png,*/*" }
      original_etag = response.headers["ETag"]

      # Sharing one ETag across formats would let a client holding the JPEG
      # revalidate into a 304 and never receive the AVIF at all.
      expect(avif_etag).to be_present
      expect(avif_etag).not_to eq(original_etag)
    end

    it "still answers a matching conditional request with 304" do
      asset = image_asset

      get "/api/v1/assets/local/#{asset.uuid}", headers: modern_accept
      etag = response.headers["ETag"]

      get "/api/v1/assets/local/#{asset.uuid}",
          headers: modern_accept.merge("If-None-Match" => etag)

      expect(response).to have_http_status(:not_modified)
      expect(response.headers["Vary"]).to include("Accept")
    end

    it "honours an explicit ?output=avif regardless of Accept" do
      asset = image_asset

      get "/api/v1/assets/local/#{asset.uuid}", params: { output: "avif" },
                                                headers: { "Accept" => "*/*" }

      expect(response.media_type).to eq("image/avif")
    end

    it "ignores an ?output= this pipeline does not produce" do
      asset = image_asset

      get "/api/v1/assets/local/#{asset.uuid}", params: { output: "tiff" },
                                                headers: modern_accept

      expect(response.media_type).to eq("image/jpeg")
    end

    it "does not transcode an SVG" do
      FileUtils.cp(dam_dir.join("hero.jpg"), dam_dir.join("vector.svg"))
      asset = image_asset(content_type: "image/svg+xml", path: "image_delivery_spec/vector.svg")

      get "/api/v1/assets/local/#{asset.uuid}", headers: modern_accept

      expect(response.media_type).to eq("image/svg+xml")
    end

    it "serves the original when the transcode fails rather than erroring" do
      asset = image_asset
      allow(ImageDelivery::Derivative).to receive(:fetch).and_return(nil)

      get "/api/v1/assets/local/#{asset.uuid}", headers: modern_accept

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/jpeg")
    end
  end

  describe "with the allow-list off" do
    it "serves the original when no CDN configuration is active" do
      asset = image_asset

      get "/api/v1/assets/local/#{asset.uuid}", headers: modern_accept

      # The feature stays off until an administrator turns it on.
      expect(response.media_type).to eq("image/jpeg")
    end

    it "serves the original when only WebP is enabled and the client prefers AVIF" do
      enable_formats("webp")
      asset = image_asset

      get "/api/v1/assets/local/#{asset.uuid}", headers: modern_accept

      expect(response.media_type).to eq("image/webp")
    end
  end

  describe "non-image delivery" do
    it "leaves a text file untouched" do
      File.binwrite(dam_dir.join("notes.txt"), "plain body")
      enable_formats("avif")
      asset = image_asset(content_type: "text/plain", path: "image_delivery_spec/notes.txt")

      get "/api/v1/assets/local/#{asset.uuid}", headers: modern_accept

      expect(response.body).to eq("plain body")
      expect(response.media_type).to eq("text/plain")
    end
  end
end
