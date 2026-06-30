# Sidekiq worker that processes a newly staged {AssetVersion} binary.
#
# This worker is the core of the post-upload pipeline.  It is enqueued by
# {Api::V1::AssetsController#dispatch_asset_workers} immediately after the
# upload transaction commits and handles everything that is too slow for a
# synchronous HTTP request:
#
# 1. **Naming-convention parsing** — extracts +dam:product_id+,
#    +dam:language_code+, and +dam:asset_type+ from filenames that follow the
#    +ProductID-LanguageCode-AssetTypeCode.ext+ convention.
#
# 2. **Universal metadata extraction** — SHA-256 checksum, file size, and
#    MIME type (via Marcel) for every file type.
#
# 3. **Image-specific enrichment** (when +content_type+ starts with +image/+):
#    - Dimensions, aspect ratio, colour space, and EXIF data via MiniMagick.
#    - Top-5 dominant colour palette via ImageMagick histogram output.
#    - Visible text via Tesseract OCR (+rtesseract+ gem).
#
# 4. **PDF detection** — stamps +document_type: "PDF"+ for PDF files.
#
# 5. **Storage** — writes the staged file to the active {StorageBackend} at
#    a versioned path (+{uuid}/v{n}_{hex}.{ext}+) and deletes the staging copy.
#
# 6. **Status promotion** — marks the parent {Asset} as +ready+ on success or
#    +failed+ when retries are exhausted.
#
# 7. **Workflow trigger** — enqueues {AssetWorkflowTriggerWorker} with the
#    +on_upload+ event once the asset is ready.
#
# == Queue & retry policy
#
# * Queue:  +ingest+
# * Retries: 3 (automatic Sidekiq back-off)
# * On exhaustion: asset marked +failed+; staging file removed.
#
# @see AssetWorkflowTriggerWorker
# @see StorageManager
# @see Api::V1::AssetsController#dispatch_asset_workers
require "digest"

class AssetProcessorWorker
  include Sidekiq::Worker
  sidekiq_options queue: "ingest", retry: 3

  # Called when all retry attempts have been exhausted.
  # Marks the parent asset as +failed+ and cleans up the staging file.
  sidekiq_retries_exhausted do |msg, exception|
    version_id   = msg["args"].first
    staging_path = msg["args"][1]

    version = AssetVersion.find_by(id: version_id)
    version.asset.update!(status: "failed") if version&.asset

    File.delete(staging_path) if staging_path && File.exist?(staging_path)
    Rails.logger.error "💥 AssetVersion #{version_id} permanently failed: #{exception.message}"
  end

  # Processes the staged binary for the given {AssetVersion}.
  #
  # @param version_id   [Integer]      the database ID of the {AssetVersion} to process
  # @param staging_path [String, nil]  absolute path to the temporary upload file;
  #   when +nil+ a mock binary is stored instead (useful in tests)
  # @return [void]
  def perform(version_id, staging_path = nil)
    version = AssetVersion.find_by(id: version_id)
    return unless version

    asset = version.asset
    asset.update!(status: "processing")

    begin
      backend = ::StorageBackend.find_by(active: true)
      storage = ::StorageManager.adapter_for(backend)

      extracted_meta = {}

      # Extract naming-convention metadata from the original filename.
      original_name = asset.properties&.dig("original_filename").to_s
      name_meta     = parse_product_filename(original_name)
      extracted_meta.merge!(name_meta) if name_meta

      if staging_path && File.exist?(staging_path)
        extracted_meta[:size]             = File.size(staging_path)
        extracted_meta[:checksum_sha256]  = Digest::SHA256.file(staging_path).hexdigest

        file_stream = File.open(staging_path)
        mime_type   = Marcel::MimeType.for(file_stream, name: File.basename(staging_path))
        extracted_meta[:content_type] = mime_type
        file_stream.close

        if mime_type.start_with?("image/")
          extract_image_metadata(staging_path, extracted_meta)
          extract_text_from_image(staging_path, extracted_meta)
        elsif mime_type == "application/pdf"
          extract_pdf_metadata(staging_path, extracted_meta)
        elsif mime_type.start_with?("video/")
          extracted_meta[:format] = "Video Media"
        end

        safe_ext  = Marcel::Magic.new(mime_type)&.extensions&.first || "bin"
        file_path = "#{asset.uuid}/v#{version.version_number}_#{SecureRandom.hex(4)}.#{safe_ext}"

        File.open(staging_path, "rb") { |file| storage.store(file, file_path) }
        File.delete(staging_path)
      else
        file_path = "#{asset.uuid}/v#{version.version_number}_mock.bin"
        storage.store(StringIO.new("Mock data"), file_path)
        extracted_meta[:content_type] = "application/octet-stream"
      end

      current_props = version.properties.is_a?(Hash) ? version.properties : {}
      version.update!(
        properties: current_props.merge(extracted_meta).merge(
          storage_path: file_path,
          processed_at: Time.current
        )
      )

      asset.update!(
        status: "ready",
        properties: asset.properties.merge(extracted_meta.stringify_keys).merge(
          "storage_path" => file_path
        )
      )

      AssetWorkflowTriggerWorker.perform_async(asset.id, "on_upload") if defined?(AssetWorkflowTriggerWorker)

      # Enqueue duplicate detection if a checksum was extracted.
      sha256 = extracted_meta[:checksum_sha256]
      if sha256.present?
        DuplicateDetectionWorker.perform_async(asset.id, sha256, asset.user_id)
      end

      Rails.logger.info "✅ AssetVersion #{version.id} processed and stored as #{file_path}"

    rescue StandardError => e
      Rails.logger.warn "⚠️ Worker failed for AssetVersion #{version.id}: #{e.message}"
      raise e
    end
  end

  private

  # Extracts DAM naming-convention fields from a filename.
  #
  # @param filename [String]
  # @return [Hash, nil] with keys +'dam:product_id'+, +'dam:language_code'+,
  #   +'dam:asset_type'+; or +nil+ when the convention is not matched
  def parse_product_filename(filename)
    return nil if filename.blank?

    base  = File.basename(filename, File.extname(filename))
    parts = base.split("-")
    return nil if parts.length < 3

    asset_type_code = parts.last.to_s.upcase
    language_code   = parts[-2].to_s.downcase
    product_id      = parts[0...-2].join("-")

    return nil unless asset_type_code.match?(/\A[A-Z]{2}\d{2}\z/)

    {
      "dam:product_id"    => product_id,
      "dam:language_code" => language_code,
      "dam:asset_type"    => asset_type_code,
    }
  end

  # Extracts image dimensions, aspect ratio, colour space, EXIF data, and
  # dominant colour palette using MiniMagick.
  #
  # @param path [String] absolute path to the image file
  # @param meta [Hash]   mutable metadata hash to populate
  # @return [void]
  def extract_image_metadata(path, meta)
    require "mini_magick"
    image = MiniMagick::Image.open(path)

    meta[:width]        = image.width
    meta[:height]       = image.height
    meta[:aspect_ratio] = (image.width.to_f / image.height).round(2)
    meta[:resolution]   = "#{image.width} x #{image.height}"
    meta[:color_space]  = image.colorspace

    extract_color_palette(path, meta)

    exif = image.exif
    if exif.any?
      meta[:camera_make]  = exif["Make"]&.strip
      meta[:camera_model] = exif["Model"]&.strip
      meta[:software]     = exif["Software"]&.strip
    end
  rescue StandardError => e
    Rails.logger.error "Minor error: Image metadata extraction failed: #{e.message}"
    meta[:image_analysis_status] = "failed"
  end

  # Extracts the top 5 dominant hex colour codes from an image using an
  # ImageMagick histogram.
  #
  # @param path [String] absolute path to the image file
  # @param meta [Hash]   mutable metadata hash; populates +:color_palette+
  # @return [void]
  def extract_color_palette(path, meta)
    output = MiniMagick::Tool::Convert.new(false) do |convert|
      convert << path
      convert << "-format" << "%c"
      convert << "-colors" << "5"
      convert << "-depth"  << "8"
      convert << "histogram:info:-"
    end

    hex_codes            = output.scan(/#[0-9A-Fa-f]{6}/).uniq
    meta[:color_palette] = hex_codes
  rescue StandardError => e
    Rails.logger.error "Color palette extraction failed: #{e.message}"
    meta[:color_palette] = []
  end

  # Runs Tesseract OCR on an image and stores any extracted text in +:extracted_text+.
  #
  # Non-fatal: failures are logged and silently suppressed so OCR unavailability
  # never prevents an asset from being stored.
  #
  # @param path [String] absolute path to the image file
  # @param meta [Hash]   mutable metadata hash; populates +:extracted_text+
  # @return [void]
  def extract_text_from_image(path, meta)
    require "rtesseract"
    image          = RTesseract.new(path)
    extracted_text = image.to_s.strip

    if extracted_text.present?
      meta[:extracted_text] = extracted_text
      Rails.logger.info "📝 OCR Extracted #{extracted_text.length} characters."
    end
  rescue StandardError => e
    Rails.logger.error "OCR extraction failed: #{e.message}"
  end

  # Stamps basic PDF metadata.  Extended PDF parsing can be added here.
  #
  # @param path [String] absolute path to the PDF file
  # @param meta [Hash]   mutable metadata hash
  # @return [void]
  def extract_pdf_metadata(path, meta)
    meta[:document_type] = "PDF"
  end
end
