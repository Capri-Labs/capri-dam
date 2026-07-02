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

    described_class.new.perform(version.id, staging_path.to_s)

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

  it "returns early when the asset version is missing" do
    expect { described_class.new.perform(0) }.not_to raise_error
    expect(storage).not_to have_received(:store)
  end

  it "logs and reraises storage errors" do
    allow(storage).to receive(:store).and_raise(StandardError, "disk full")

    expect { described_class.new.perform(version.id) }.to raise_error(StandardError, "disk full")
    expect(asset.reload.read_attribute_before_type_cast("status")).to eq(Asset.statuses["processing"].to_s)
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
    convert_class = class_double(
      "MiniMagick::Tool::Convert",
      new: "  4: (170,187,204) #AABBCC srgb(170,187,204)\n"
    )
    stub_const("MiniMagick::Image", image_class)
    stub_const("MiniMagick::Tool::Convert", convert_class)

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
    convert = double("MiniMagick::Tool::Convert")
    allow(convert).to receive(:background)
    allow(convert).to receive(:flatten)
    allow(convert).to receive(:<<) do |arg|
      File.binwrite(arg, preview_bytes) if arg.to_s.end_with?(".png")
    end
    allow(MiniMagick::Tool::Convert).to receive(:new).and_yield(convert)

    meta = {}
    worker.send(:generate_web_preview, "/tmp/source.psd", asset, version, storage, meta)

    expect(meta[:preview_content_type]).to eq("image/png")
    expect(meta[:preview_storage_path]).to match(%r{\A#{asset.uuid}/v1_preview_[0-9a-f]+\.png\z})
    expect(storage).to have_received(:store)
  end

  it "falls back to an empty color palette when ImageMagick fails" do
    meta = {}
    worker = described_class.new
    convert_class = class_double("MiniMagick::Tool::Convert")
    allow(convert_class).to receive(:new).and_raise(StandardError, "convert failed")
    stub_const("MiniMagick::Tool::Convert", convert_class)

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
end
