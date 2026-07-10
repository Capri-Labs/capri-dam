require "rails_helper"

RSpec.describe AssetProcessorWorker, type: :worker do
  let(:asset) do
    create(
      :asset,
      status: :pending,
      properties: { "original_filename" => "SKU-123-en-HR01.pdf" }
    )
  end
  let(:version) { create(:asset_version, asset: asset, version_number: 1, properties: nil) }
  let(:storage) { instance_double("StorageAdapter", store: true) }

  before do
    create(:storage_backend, active: true)
    allow(StorageManager).to receive(:adapter_for).and_return(storage)
    allow(AssetWorkflowTriggerWorker).to receive(:perform_async)
    allow(DuplicateDetectionWorker).to receive(:perform_async)
  end

  it "stores a missing staging file as a mock binary and marks the asset ready" do
    described_class.new.perform(version.id)

    expect(storage).to have_received(:store).with(instance_of(StringIO), a_string_ending_with("_mock.bin"))
    expect(asset.reload.read_attribute_before_type_cast("status")).to eq(Asset.statuses["ready"].to_s)
    expect(version.reload.properties).to include("content_type" => "application/octet-stream")
    expect(AssetWorkflowTriggerWorker).to have_received(:perform_async).with(asset.id, "on_upload")
  end

  it "extracts file metadata, naming metadata, pdf metadata and enqueues duplicate detection" do
    staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.pdf")
    File.binwrite(staging_path, "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n")

    worker = described_class.new
    allow(worker).to receive(:generate_web_preview)
    worker.perform(version.id, staging_path.to_s)

    props = version.reload.properties
    expect(props).to include(
      "document_type" => "PDF",
      "dam:product_id" => "SKU-123",
      "dam:language_code" => "en",
      "dam:asset_type" => "HR01"
    )
    expect(props["checksum_sha256"]).to be_present
    expect(File.exist?(staging_path)).to be(false)
    expect(DuplicateDetectionWorker).to have_received(:perform_async).with(asset.id, props["checksum_sha256"], asset.user_id)
  ensure
    File.delete(staging_path) if staging_path && File.exist?(staging_path)
  end

  it "extracts image metadata and OCR text for image uploads" do
    staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.png")
    File.binwrite(staging_path, "\x89PNG\r\n\x1A\n".b)
    worker = described_class.new
    allow(worker).to receive(:extract_image_metadata) do |_path, meta|
      meta[:width] = 100
      meta[:height] = 50
    end
    allow(worker).to receive(:extract_text_from_image) do |_path, meta|
      meta[:extracted_text] = "Visible label"
    end

    worker.perform(version.id, staging_path.to_s)

    expect(worker).to have_received(:extract_image_metadata).with(staging_path.to_s, instance_of(Hash))
    expect(worker).to have_received(:extract_text_from_image).with(staging_path.to_s, instance_of(Hash))
    expect(version.reload.properties).to include(
      "width" => 100,
      "height" => 50,
      "extracted_text" => "Visible label",
      "content_type" => "image/png"
    )
  ensure
    File.delete(staging_path) if staging_path && File.exist?(staging_path)
  end

  it "marks video uploads with a video media format" do
    staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.mp4")
    File.binwrite(staging_path, "video bytes")
    allow(Marcel::MimeType).to receive(:for).and_return("video/mp4")

    described_class.new.perform(version.id, staging_path.to_s)

    expect(version.reload.properties).to include(
      "content_type" => "video/mp4",
      "format" => "Video Media"
    )
  ensure
    File.delete(staging_path) if staging_path && File.exist?(staging_path)
  end

  describe "3D model uploads" do
    it "tags a GLB upload with a 3D Model format and marks it renderable, without generating a preview" do
      staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.glb")
      File.binwrite(staging_path, "glb bytes")
      allow(Marcel::MimeType).to receive(:for).and_return("model/gltf-binary")

      worker = described_class.new
      allow(worker).to receive(:generate_web_preview)
      worker.perform(version.id, staging_path.to_s)

      expect(version.reload.properties).to include(
        "content_type" => "model/gltf-binary",
        "format" => "3D Model",
        "model_3d_renderable" => true
      )
      expect(worker).not_to have_received(:generate_web_preview)
    ensure
      File.delete(staging_path) if staging_path && File.exist?(staging_path)
    end

    it "tags a GLTF upload the same way as GLB" do
      staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.gltf")
      File.binwrite(staging_path, "{}")
      allow(Marcel::MimeType).to receive(:for).and_return("model/gltf+json")

      described_class.new.perform(version.id, staging_path.to_s)

      expect(version.reload.properties).to include(
        "content_type" => "model/gltf+json",
        "format" => "3D Model",
        "model_3d_renderable" => true
      )
    ensure
      File.delete(staging_path) if staging_path && File.exist?(staging_path)
    end

    it "tags an OBJ upload as 3D Model and renderable (three.js path)" do
      staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.obj")
      File.binwrite(staging_path, "v 0 0 0")
      allow(Marcel::MimeType).to receive(:for).and_return("application/x-tgif")

      described_class.new.perform(version.id, staging_path.to_s)

      expect(version.reload.properties).to include(
        "content_type" => "application/x-tgif",
        "format" => "3D Model",
        "model_3d_renderable" => true
      )
    ensure
      File.delete(staging_path) if staging_path && File.exist?(staging_path)
    end

    it "tags an STL upload as 3D Model and renderable (three.js path)" do
      staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.stl")
      File.binwrite(staging_path, "solid test")
      allow(Marcel::MimeType).to receive(:for).and_return("application/vnd.ms-pki.stl")

      described_class.new.perform(version.id, staging_path.to_s)

      expect(version.reload.properties).to include(
        "content_type" => "application/vnd.ms-pki.stl",
        "format" => "3D Model",
        "model_3d_renderable" => true
      )
    ensure
      File.delete(staging_path) if staging_path && File.exist?(staging_path)
    end

    it "tags a USDZ upload as 3D Model but not renderable (no in-page WebGL renderer)" do
      staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.usdz")
      File.binwrite(staging_path, "usdz bytes")
      allow(Marcel::MimeType).to receive(:for).and_return("model/vnd.usdz+zip")

      described_class.new.perform(version.id, staging_path.to_s)

      expect(version.reload.properties).to include(
        "content_type" => "model/vnd.usdz+zip",
        "format" => "3D Model",
        "model_3d_renderable" => false
      )
    ensure
      File.delete(staging_path) if staging_path && File.exist?(staging_path)
    end

    it "tags an Adobe Dimension (.dn) upload as 3D Model but not renderable" do
      staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.dn")
      File.binwrite(staging_path, "dn bytes")
      allow(Marcel::MimeType).to receive(:for).and_return("model/x-adobe-dn")

      described_class.new.perform(version.id, staging_path.to_s)

      expect(version.reload.properties).to include(
        "content_type" => "model/x-adobe-dn",
        "format" => "3D Model",
        "model_3d_renderable" => false
      )
    ensure
      File.delete(staging_path) if staging_path && File.exist?(staging_path)
    end
  end

  it "returns early when the asset version is missing" do
    expect { described_class.new.perform(0) }.not_to raise_error
    expect(storage).not_to have_received(:store)
  end

  it "logs and reraises storage errors" do
    allow(storage).to receive(:store).and_raise(StandardError, "disk full")

    expect { described_class.new.perform(version.id) }.to raise_error(StandardError, "disk full")
    expect(asset.reload.read_attribute_before_type_cast("status")).to eq(Asset.statuses["processing"].to_s)
  end

  it "stores unknown staged files with a fallback extension and without workflow hooks" do
    staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.unknown")
    File.binwrite(staging_path, "opaque bytes")
    allow(AssetVersion).to receive(:find_by).with(id: version.id).and_return(version)
    allow(version).to receive(:asset).and_return(asset)
    allow(asset).to receive(:properties).and_return(nil)
    hide_const("AssetWorkflowTriggerWorker")
    allow(Marcel::MimeType).to receive(:for).and_return("application/x-opaque")
    allow(Marcel::Magic).to receive(:new).and_return(instance_double("Marcel::Magic", extensions: nil))

    described_class.new.perform(version.id, staging_path.to_s)

    expect(version.reload.properties["storage_path"]).to match(%r{\A#{asset.uuid}/v1_[0-9a-f]+\.bin\z})
    expect(version.properties).not_to have_key("dam:product_id")
    expect(Asset.find(asset.id).properties["content_type"]).to eq("application/x-opaque")
    expect(DuplicateDetectionWorker).to have_received(:perform_async)
  ensure
    File.delete(staging_path) if staging_path && File.exist?(staging_path)
  end

  it "handles private image helper failures without aborting processing" do
    meta = {}
    worker = described_class.new
    image_class = class_double("MiniMagick::Image")
    allow(image_class).to receive(:open).and_raise(StandardError, "bad image")
    stub_const("MiniMagick::Image", image_class)

    worker.send(:extract_image_metadata, "missing.jpg", meta)

    expect(meta).to include(image_analysis_status: "failed")
  end

  it "captures image dimensions, exif fields and dominant colors" do
    meta = {}
    worker = described_class.new
    image = instance_double(
      "MiniMagick::Image",
      width: 320,
      height: 160,
      colorspace: "sRGB",
      type: "JPEG",
      layers: [],
      exif: { "Make" => " Canon ", "Model" => "R5 ", "Software" => "DPP " }
    )
    allow(image).to receive(:[]).and_return(nil)
    image_class = class_double("MiniMagick::Image", open: image)
    stub_const("MiniMagick::Image", image_class)
    allow(MiniMagick).to receive(:convert)
      .and_return("  4: (170,187,204) #AABBCC srgb(170,187,204)\n")

    worker.send(:extract_image_metadata, "image.jpg", meta)

    expect(meta).to include(
      width: 320,
      height: 160,
      aspect_ratio: 2.0,
      resolution: "320 x 160",
      color_space: "sRGB",
      color_palette: [ "#AABBCC" ],
      camera_make: "Canon",
      camera_model: "R5",
      software: "DPP"
    )
    expect(meta[:exif_data]).to eq(
      "Make" => "Canon", "Model" => "R5", "Software" => "DPP"
    )
  end

  describe "#extract_embedded_metadata" do
    let(:exiftool_json) do
      [ {
        "SourceFile" => "image.jpg",
        "ExifTool:ExifToolVersion" => 13.55,
        "File:FileName" => "image.jpg",
        "EXIF:Make" => "NIKON CORPORATION",
        "EXIF:Model" => "NIKON D850",
        "EXIF:ThumbnailImage" => "(Binary data 3543 bytes, use -b option to extract)",
        "IPTC:CopyrightNotice" => "ALDI US",
        "XMP:Creator" => [ "Andy Thoma" ],
        "XMP:Lens" => "Nikon AF-S NIKKOR 24-70mm f/2.8E ED VR",
        "XMP:ColorMode" => "CMYK",
        "XMP:DocumentID" => "adobe:docid:photoshop:abc",
        "XMP:CreateDate" => "2026:02:09 20:33:26",
        "ICC_Profile:ProfileDescription" => "Coated GRACoL 2006",
        "Photoshop:PhotoshopQuality" => 12,
      } ].to_json
    end

    it "merges the full embedded metadata and promotes descriptive fields" do
      worker = described_class.new
      allow(worker).to receive(:exiftool_available?).and_return(true)
      allow(Open3).to receive(:capture3).and_return([ exiftool_json, "", instance_double(Process::Status, success?: true) ])

      meta = { exif_data: { "Make" => "NIKON CORPORATION" } }
      worker.send(:extract_embedded_metadata, "image.jpg", meta)

      grouped = meta[:embedded_metadata]
      expect(grouped.keys).to contain_exactly("EXIF", "IPTC", "XMP", "ICC_Profile", "Photoshop")
      expect(grouped["EXIF"]).not_to have_key("ThumbnailImage")
      expect(grouped).not_to have_key("SourceFile")
      expect(grouped).not_to have_key("ExifTool")
      expect(grouped).not_to have_key("File")
      expect(meta[:metadata_field_count]).to eq(grouped.values.sum(&:size))
      expect(meta).to include(
        creator: [ "Andy Thoma" ],
        copyright: "ALDI US",
        lens: "Nikon AF-S NIKKOR 24-70mm f/2.8E ED VR",
        camera_make: "NIKON CORPORATION",
        camera_model: "NIKON D850",
        color_mode: "CMYK",
        icc_profile: "Coated GRACoL 2006",
        document_id: "adobe:docid:photoshop:abc",
        date_taken: "2026:02:09 20:33:26"
      )
      expect(meta[:exif_data]).to include("Make" => "NIKON CORPORATION", "Model" => "NIKON D850")
    end

    it "maps embedded metadata onto schema map_to_property keys" do
      worker = described_class.new
      allow(worker).to receive(:exiftool_available?).and_return(true)
      allow(Open3).to receive(:capture3).and_return([ exiftool_json, "", instance_double(Process::Status, success?: true) ])

      meta = {}
      worker.send(:extract_embedded_metadata, "image.jpg", meta)

      expect(meta[:"dc:creator"]).to eq([ "Andy Thoma" ])
      expect(meta[:"dc:rights"]).to eq("ALDI US")
      expect(meta[:"dc:date"]).to eq("2026-02-09")
      expect(meta[:"tiff:Make"]).to eq("NIKON CORPORATION")
      expect(meta[:"tiff:Model"]).to eq("NIKON D850")
    end

    it "does not overwrite existing schema-mapped values" do
      worker = described_class.new
      allow(worker).to receive(:exiftool_available?).and_return(true)
      allow(Open3).to receive(:capture3).and_return([ exiftool_json, "", instance_double(Process::Status, success?: true) ])

      meta = { "dc:rights" => "Manual override" }
      worker.send(:extract_embedded_metadata, "image.jpg", meta)

      expect(meta["dc:rights"]).to eq("Manual override")
      expect(meta[:"dc:rights"]).to be_nil
    end

    it "no-ops gracefully when exiftool is unavailable" do
      worker = described_class.new
      allow(worker).to receive(:exiftool_available?).and_return(false)
      expect(Open3).not_to receive(:capture3)

      meta = {}
      worker.send(:extract_embedded_metadata, "image.jpg", meta)

      expect(meta).to be_empty
    end

    it "no-ops when the exiftool command fails" do
      worker = described_class.new
      allow(worker).to receive(:exiftool_available?).and_return(true)
      allow(Open3).to receive(:capture3).and_return([ "", "boom", instance_double(Process::Status, success?: false) ])

      meta = {}
      worker.send(:extract_embedded_metadata, "image.jpg", meta)

      expect(meta).to be_empty
    end

    it "ignores non-hash exiftool payloads" do
      worker = described_class.new
      allow(worker).to receive(:exiftool_available?).and_return(true)
      allow(Open3).to receive(:capture3).and_return([ [ "not-a-hash" ].to_json, "", instance_double(Process::Status, success?: true) ])

      meta = { exif_data: { "Make" => "Canon" } }
      worker.send(:extract_embedded_metadata, "image.jpg", meta)

      expect(meta).to eq(exif_data: { "Make" => "Canon" })
    end

    it "ignores exiftool payloads that only contain skipped or binary fields" do
      worker = described_class.new
      allow(worker).to receive(:exiftool_available?).and_return(true)
      allow(Open3).to receive(:capture3).and_return([
        [ {
          "SourceFile" => "image.jpg",
          "EXIF:ThumbnailImage" => "(Binary data 12 bytes, use -b option to extract)",
        } ].to_json,
        "",
        instance_double(Process::Status, success?: true),
      ])

      meta = {}
      worker.send(:extract_embedded_metadata, "image.jpg", meta)

      expect(meta).to be_empty
    end

    it "keeps XMP metadata without forcing an EXIF merge and skips blank descriptive fallbacks" do
      worker = described_class.new
      allow(worker).to receive(:exiftool_available?).and_return(true)
      allow(Open3).to receive(:capture3).and_return([
        [ {
          "XMP:Creator" => "   ",
          "IPTC:By-line" => [],
          "XMP:Headline" => "  Launch Story  ",
        } ].to_json,
        "",
        instance_double(Process::Status, success?: true),
      ])

      meta = {}
      worker.send(:extract_embedded_metadata, "image.jpg", meta)

      expect(meta[:embedded_metadata]).to eq(
        "EXIF" => {},
        "XMP" => { "Creator" => "   ", "Headline" => "  Launch Story  " },
        "IPTC" => { "By-line" => [] }
      )
      expect(meta[:exif_data]).to be_nil
      expect(meta[:creator]).to be_nil
      expect(meta[:headline]).to eq("Launch Story")
    end
  end

  it "generates a web preview for non-web-renderable image formats (PSD)" do
    staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.psd")
    File.binwrite(staging_path, "8BPS".b)
    allow(Marcel::MimeType).to receive(:for).and_return("image/vnd.adobe.photoshop")

    worker = described_class.new
    allow(worker).to receive(:extract_image_metadata)
    allow(worker).to receive(:extract_text_from_image)
    allow(worker).to receive(:generate_web_preview) do |_src, _asset, _version, _storage, meta|
      meta[:preview_storage_path] = "uuid/v1_preview_abcd.png"
      meta[:preview_content_type] = "image/png"
    end

    worker.perform(version.id, staging_path.to_s)

    expect(worker).to have_received(:generate_web_preview)
    expect(version.reload.properties).to include(
      "preview_storage_path" => "uuid/v1_preview_abcd.png",
      "preview_content_type" => "image/png"
    )
  ensure
    File.delete(staging_path) if staging_path && File.exist?(staging_path)
  end

  it "generates a web preview for document formats (PDF)" do
    staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.pdf")
    File.binwrite(staging_path, "%PDF-1.4".b)
    allow(Marcel::MimeType).to receive(:for).and_return("application/pdf")

    worker = described_class.new
    allow(worker).to receive(:extract_pdf_metadata)
    allow(worker).to receive(:generate_web_preview) do |_src, _asset, _version, meta_storage, meta|
      meta[:preview_storage_path] = "uuid/v1_preview_pdf.png"
      meta[:preview_content_type] = "image/png"
    end

    worker.perform(version.id, staging_path.to_s)

    expect(worker).to have_received(:generate_web_preview)
    expect(version.reload.properties).to include(
      "preview_storage_path" => "uuid/v1_preview_pdf.png",
      "preview_content_type" => "image/png"
    )
  ensure
    File.delete(staging_path) if staging_path && File.exist?(staging_path)
  end

  it "generates a web preview for vector / document formats (EPS, AI, INDD)" do
    AssetProcessorWorker::PREVIEWABLE_DOCUMENT_MIME_TYPES
      .reject { |m| m == "application/pdf" }
      .each do |mime|
      staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.bin")
      File.binwrite(staging_path, "data".b)
      allow(Marcel::MimeType).to receive(:for).and_return(mime)

      doc_version = create(
        :asset_version,
        asset: create(:asset, status: :pending),
        version_number: 1,
        properties: nil
      )

      worker = described_class.new
      allow(worker).to receive(:generate_web_preview) do |_src, _asset, _v, _storage, meta|
        meta[:preview_storage_path] = "uuid/v1_preview_doc.png"
        meta[:preview_content_type] = "image/png"
      end

      worker.perform(doc_version.id, staging_path.to_s)

      expect(worker).to have_received(:generate_web_preview), "expected preview for #{mime}"
      expect(doc_version.reload.properties).to include(
        "preview_storage_path" => "uuid/v1_preview_doc.png",
        "format" => "Vector / Document Media"
      )
    ensure
      File.delete(staging_path) if staging_path && File.exist?(staging_path)
    end
  end

  it "does not generate a web preview for browser-renderable images (PNG)" do
    staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.png")
    File.binwrite(staging_path, "\x89PNG\r\n\x1A\n".b)

    worker = described_class.new
    allow(worker).to receive(:extract_image_metadata)
    allow(worker).to receive(:extract_text_from_image)
    allow(worker).to receive(:generate_web_preview)

    worker.perform(version.id, staging_path.to_s)

    expect(worker).not_to have_received(:generate_web_preview)
  ensure
    File.delete(staging_path) if staging_path && File.exist?(staging_path)
  end

  it "stores a preview path and content type via generate_web_preview" do
    worker = described_class.new
    preview_bytes = "PNGDATA"
    convert = double("MiniMagick convert")
    allow(convert).to receive(:background)
    allow(convert).to receive(:flatten)
    allow(convert).to receive(:<<) do |arg|
      File.binwrite(arg, preview_bytes) if arg.to_s.end_with?(".png")
    end
    allow(MiniMagick).to receive(:convert).and_yield(convert)

    meta = {}
    worker.send(:generate_web_preview, "/tmp/source.psd", asset, version, storage, meta)

    expect(meta[:preview_content_type]).to eq("image/png")
    expect(meta[:preview_storage_path]).to match(%r{\A#{asset.uuid}/v1_preview_[0-9a-f]+\.png\z})
    expect(storage).to have_received(:store)
  end

  describe "#backfill_preview" do
    let(:psd_asset) do
      create(
        :asset,
        status: :ready,
        properties: {
          "original_filename" => "design.psd",
          "content_type" => "image/vnd.adobe.photoshop",
          "storage_path" => "uuid/v1_abc.psd",
        }
      )
    end
    let!(:psd_version) do
      create(:asset_version, asset: psd_asset, version_number: 1,
                             properties: { "storage_path" => "uuid/v1_abc.psd" })
    end

    it "generates and stamps a preview for a non-web image missing one" do
      worker = described_class.new
      allow(worker).to receive(:fetch_original).and_return(true)
      allow(worker).to receive(:generate_web_preview) do |_src, _asset, _version, _storage, meta|
        meta[:preview_storage_path] = "uuid/v1_preview_dead.png"
        meta[:preview_content_type] = "image/png"
      end

      result = worker.backfill_preview(psd_asset)

      expect(result).to eq("uuid/v1_preview_dead.png")
      expect(psd_asset.reload.properties).to include(
        "preview_storage_path" => "uuid/v1_preview_dead.png",
        "preview_content_type" => "image/png"
      )
      expect(psd_version.reload.properties["preview_storage_path"]).to eq("uuid/v1_preview_dead.png")
    end

    it "skips web-renderable images" do
      png = create(:asset, status: :ready,
                           properties: { "content_type" => "image/png", "storage_path" => "uuid/v1.png" })
      create(:asset_version, asset: png, version_number: 1, properties: { "storage_path" => "uuid/v1.png" })

      expect(described_class.new.backfill_preview(png)).to be_nil
    end

    it "skips assets without an active version" do
      orphan = create(:asset, status: :ready, properties: { "content_type" => "image/vnd.adobe.photoshop" })

      expect(described_class.new.backfill_preview(orphan)).to be_nil
    end

    it "skips assets that already have a preview" do
      psd_version.update!(properties: psd_version.properties.merge("preview_storage_path" => "uuid/existing.png"))

      expect(described_class.new.backfill_preview(psd_asset)).to be_nil
    end

    it "skips assets without a stored original path" do
      no_source = create(:asset, status: :ready, properties: { "content_type" => "image/vnd.adobe.photoshop" })
      create(:asset_version, asset: no_source, version_number: 1, properties: nil)

      expect(described_class.new.backfill_preview(no_source)).to be_nil
    end

    it "skips when the original cannot be fetched" do
      worker = described_class.new
      allow(worker).to receive(:fetch_original).and_return(false)
      expect(worker).not_to receive(:generate_web_preview)

      expect(worker.backfill_preview(psd_asset)).to be_nil
    end

    it "cleans up fetched originals when preview generation does not produce a path" do
      worker = described_class.new
      fetched_path = nil
      allow(worker).to receive(:fetch_original) do |_storage, _storage_path, tmp|
        fetched_path = tmp
        File.binwrite(tmp, "source")
        true
      end
      allow(worker).to receive(:generate_web_preview)

      expect(worker.backfill_preview(psd_asset)).to be_nil
      expect(fetched_path).to be_present
      expect(File.exist?(fetched_path)).to be(false)
    end
  end

  describe "#parse_product_filename" do
    it "returns nil for filenames without enough dash-separated parts" do
      expect(described_class.new.send(:parse_product_filename, "poster.jpg")).to be_nil
    end
  end

  describe "#clean_exif" do
    it "drops blank keys and blank values while preserving non-string values" do
      cleaned = described_class.new.send(:clean_exif, {
        "" => "skip",
        "ExposureTime" => 0.5,
        "BlankValue" => "   ",
        "NilValue" => nil,
      })

      expect(cleaned).to eq("ExposureTime" => 0.5)
    end
  end

  describe "#extract_extended_image_properties" do
    it "records technical image fields when they are present" do
      image = instance_double("MiniMagick::Image", type: "PSD", layers: [ :bg, :text ])
      allow(image).to receive(:[]).with("%[bit-depth]").and_return("16")
      allow(image).to receive(:[]).with("%[channels]").and_return("rgba")
      allow(image).to receive(:[]).with("%C").and_return("Zip")
      allow(image).to receive(:[]).with("%[orientation]").and_return("TopLeft")
      allow(image).to receive(:[]).with("%x x %y").and_return("300 x 300")
      allow(image).to receive(:[]).with("%[profile:icc]").and_return("Adobe RGB")

      meta = {}
      described_class.new.send(:extract_extended_image_properties, image, meta)

      expect(meta).to include(
        format: "PSD",
        bit_depth: "16",
        channels: "rgba",
        compression: "Zip",
        orientation: "TopLeft",
        dpi: "300 x 300",
        color_profile: "Adobe RGB",
        layer_count: 2
      )
    end

    it "omits layer counts when the image exposes no layers collection" do
      image = instance_double("MiniMagick::Image", type: "PNG", layers: nil)
      allow(image).to receive(:[]).and_return(nil)

      meta = {}
      described_class.new.send(:extract_extended_image_properties, image, meta)

      expect(meta).not_to have_key(:layer_count)
    end
  end

  describe ".backfill_preview" do
    it "delegates to an instance worker" do
      worker = instance_double(described_class, backfill_preview: "uuid/preview.png")
      allow(described_class).to receive(:new).and_return(worker)

      expect(described_class.backfill_preview(asset)).to eq("uuid/preview.png")
      expect(worker).to have_received(:backfill_preview).with(asset)
    end
  end

  describe "#fetch_original" do
    let(:worker) { described_class.new }
    let(:dest_path) { Rails.root.join("storage", "fetch_original_dest_#{SecureRandom.hex}.bin").to_s }

    after do
      File.delete(dest_path) if File.exist?(dest_path)
    end

    it "copies files from the local storage adapter" do
      storage = StorageAdapters::LocalStorageAdapter.new
      storage_path = "spec-fetch/source-#{SecureRandom.hex}.bin"
      source = StorageAdapters::LocalStorageAdapter::ROOT.call.join(storage_path)
      FileUtils.mkdir_p(source.dirname)
      File.binwrite(source, "source-bytes")

      expect(worker.send(:fetch_original, storage, storage_path, dest_path)).to be(true)
      expect(File.binread(dest_path)).to eq("source-bytes")
    ensure
      File.delete(source) if source && File.exist?(source)
    end

    it "returns false when a local storage source file is missing" do
      storage = StorageAdapters::LocalStorageAdapter.new

      expect(worker.send(:fetch_original, storage, "missing/source.bin", dest_path)).to be(false)
      expect(File.size?(dest_path)).to be_nil
    end

    it "downloads files from adapters exposing download" do
      remote_storage = double("RemoteStorage")
      allow(remote_storage).to receive(:download).with("remote/path.bin").and_return("remote-bytes")

      expect(worker.send(:fetch_original, remote_storage, "remote/path.bin", dest_path)).to be(true)
      expect(File.binread(dest_path)).to eq("remote-bytes")
    end

    it "returns false for unsupported adapters" do
      expect(worker.send(:fetch_original, Object.new, "remote/path.bin", dest_path)).to be(false)
    end

    it "logs and returns false when fetching raises an error" do
      remote_storage = double("RemoteStorage")
      allow(remote_storage).to receive(:download).and_raise(StandardError, "network down")

      expect(worker.send(:fetch_original, remote_storage, "remote/path.bin", dest_path)).to be(false)
      expect(File.size?(dest_path)).to be_nil
    end
  end

  describe "private error handling helpers" do
    let(:worker) { described_class.new }

    it "returns the provided default when safe_image_attr raises" do
      expect(worker.send(:safe_image_attr, "fallback") { raise StandardError, "boom" }).to eq("fallback")
    end

    it "swallows ExifTool extraction errors" do
      allow(worker).to receive(:exiftool_available?).and_return(true)
      allow(Open3).to receive(:capture3).and_raise(StandardError, "exiftool missing")

      meta = { exif_data: { "Make" => "Canon" } }
      expect { worker.send(:extract_embedded_metadata, "image.jpg", meta) }.not_to raise_error
      expect(meta).to eq(exif_data: { "Make" => "Canon" })
    end

    it "swallows preview generation failures" do
      allow(MiniMagick).to receive(:convert).and_raise(StandardError, "convert broke")

      meta = {}
      expect { worker.send(:generate_web_preview, "source.psd", asset, version, storage, meta) }.not_to raise_error
      expect(meta).to be_empty
    end

    it "passes histogram arguments to ImageMagick when extracting a color palette" do
      convert = double("MiniMagick convert")
      allow(convert).to receive(:<<).and_return(convert)
      allow(MiniMagick).to receive(:convert).and_yield(convert).and_return(
        "  4: (170,187,204) #AABBCC srgb(170,187,204)
  1: (17,34,51) #112233 srgb(17,34,51)"
      )

      meta = {}
      worker.send(:extract_color_palette, "image.jpg", meta)

      expect(convert).to have_received(:<<).with("image.jpg")
      expect(convert).to have_received(:<<).with("-format")
      expect(convert).to have_received(:<<).with("%c")
      expect(convert).to have_received(:<<).with("-colors")
      expect(convert).to have_received(:<<).with("5")
      expect(convert).to have_received(:<<).with("-depth")
      expect(convert).to have_received(:<<).with("8")
      expect(convert).to have_received(:<<).with("histogram:info:-")
      expect(meta[:color_palette]).to eq([ "#AABBCC", "#112233" ])
    end

    it "logs OCR errors without populating extracted text" do
      tesseract_class = class_double("RTesseract", new: nil)
      stub_const("RTesseract", tesseract_class)
      allow(tesseract_class).to receive(:new).and_raise(StandardError, "ocr failed")

      meta = {}
      expect { worker.send(:extract_text_from_image, "image.jpg", meta) }.not_to raise_error
      expect(meta).to eq({})
    end

    it "memoizes the exiftool availability probe" do
      worker.instance_variable_set(:@exiftool_available, true)
      allow(worker).to receive(:system)

      expect(worker.send(:exiftool_available?)).to be(true)
      expect(worker).not_to have_received(:system)
    end
  end

  it "falls back to an empty color palette when ImageMagick fails" do
    meta = {}
    worker = described_class.new
    allow(MiniMagick).to receive(:convert).and_raise(StandardError, "convert failed")

    worker.send(:extract_color_palette, "missing.jpg", meta)

    expect(meta).to include(color_palette: [])
  end

  it "stores OCR text when Tesseract returns content" do
    meta = {}
    tesseract_image = instance_double("RTesseract", to_s: "  extracted words  ")
    tesseract_class = class_double("RTesseract", new: tesseract_image)
    stub_const("RTesseract", tesseract_class)

    described_class.new.send(:extract_text_from_image, "image.jpg", meta)

    expect(meta).to include(extracted_text: "extracted words")
  end

  it "skips storing OCR text when Tesseract returns only whitespace" do
    meta = {}
    tesseract_image = instance_double("RTesseract", to_s: "   ")
    tesseract_class = class_double("RTesseract", new: tesseract_image)
    stub_const("RTesseract", tesseract_class)

    described_class.new.send(:extract_text_from_image, "image.jpg", meta)

    expect(meta).to eq({})
  end

  it "does not store a preview when ImageMagick produces no file" do
    worker = described_class.new
    convert = double("MiniMagick convert", background: nil, flatten: nil)
    allow(convert).to receive(:<<)
    allow(MiniMagick).to receive(:convert).and_yield(convert)

    meta = {}
    worker.send(:generate_web_preview, "source.psd", asset, version, storage, meta)

    expect(storage).not_to have_received(:store)
    expect(meta).to be_empty
  end

  it "marks assets failed and removes the staged file when retries are exhausted" do
    staging_path = Rails.root.join("storage", "asset_processor_worker_#{SecureRandom.hex}.bin")
    File.binwrite(staging_path, "staged")

    described_class.sidekiq_retries_exhausted_block.call(
      { "args" => [ version.id, staging_path.to_s ] },
      StandardError.new("permanent")
    )

    expect(asset.reload.read_attribute_before_type_cast("status")).to eq(Asset.statuses["failed"].to_s)
    expect(File.exist?(staging_path)).to be(false)
  ensure
    File.delete(staging_path) if staging_path && File.exist?(staging_path)
  end

  it "computes a perceptual hash from downsized greyscale pixel data" do
    worker = described_class.new
    # 9 columns x 8 rows, strictly ascending per row → every column-pair
    # comparison is "true" (left < right) so every bit is 1.
    row = (0...9).map { |i| i * 25 }
    raw_bytes = (row * 8).pack("C*")
    convert = double("MiniMagick convert")
    allow(convert).to receive(:<<).and_return(convert)
    allow(MiniMagick).to receive(:convert).and_yield(convert).and_return(raw_bytes)

    meta = {}
    worker.send(:extract_perceptual_hash, "image.jpg", meta)

    expect(convert).to have_received(:<<).with("image.jpg")
    expect(convert).to have_received(:<<).with("-colorspace")
    expect(convert).to have_received(:<<).with("Gray")
    expect(convert).to have_received(:<<).with("-resize")
    expect(convert).to have_received(:<<).with("9x8!")
    expect(meta[:perceptual_hash]).to eq("ffffffffffffffff")
  end

  it "produces perceptual hashes with a small Hamming distance for near-identical images" do
    worker = described_class.new

    row_a = (0...9).map { |i| i * 25 }
    # Row B nudges every pixel by a small delta (simulating re-encode noise)
    # but preserves the ascending order, so the resulting hash should be
    # identical or very close.
    row_b = row_a.map { |v| [ v + 3, 255 ].min }

    convert = double("MiniMagick convert")
    allow(convert).to receive(:<<).and_return(convert)
    allow(MiniMagick).to receive(:convert).and_yield(convert).and_return((row_a * 8).pack("C*"), (row_b * 8).pack("C*"))

    meta_a = {}
    meta_b = {}
    worker.send(:extract_perceptual_hash, "a.jpg", meta_a)
    worker.send(:extract_perceptual_hash, "b.jpg", meta_b)

    distance = (meta_a[:perceptual_hash].to_i(16) ^ meta_b[:perceptual_hash].to_i(16)).to_s(2).count("1")
    expect(distance).to eq(0)
  end

  it "does not set a perceptual hash when the pixel buffer is too small" do
    worker = described_class.new
    allow(MiniMagick).to receive(:convert).and_return("too short")

    meta = {}
    worker.send(:extract_perceptual_hash, "image.jpg", meta)

    expect(meta).not_to have_key(:perceptual_hash)
  end

  it "swallows perceptual hash extraction failures" do
    worker = described_class.new
    allow(MiniMagick).to receive(:convert).and_raise(StandardError, "convert broke")

    meta = {}
    expect { worker.send(:extract_perceptual_hash, "image.jpg", meta) }.not_to raise_error
    expect(meta).not_to have_key(:perceptual_hash)
  end
end
