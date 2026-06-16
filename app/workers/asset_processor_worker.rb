require 'digest'

class AssetProcessorWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'ingest', retry: 3

  # Safety net for complete failures
  sidekiq_retries_exhausted do |msg, exception|
    version_id = msg['args'].first
    staging_path = msg['args'][1]

    version = AssetVersion.find_by(id: version_id)
    version.asset.update!(status: 'failed') if version&.asset

    File.delete(staging_path) if staging_path && File.exist?(staging_path)
    Rails.logger.error "💥 AssetVersion #{version_id} permanently failed: #{exception.message}"
  end

  def perform(version_id, staging_path = nil)
    # 🚀 ARCHITECTURE FIX: We process the Version, not the Parent Asset
    version = AssetVersion.find_by(id: version_id)
    return unless version

    asset = version.asset
    asset.update!(status: 'processing')

    begin
      backend = ::StorageBackend.find_by(active: true)
      storage = ::StorageManager.adapter_for(backend)

      # 1. Initialize the enriched metadata hash
      extracted_meta = {}

      if staging_path && File.exist?(staging_path)
        # --- UNIVERSAL METADATA ---
        extracted_meta[:size] = File.size(staging_path)
        extracted_meta[:checksum_sha256] = Digest::SHA256.file(staging_path).hexdigest

        # Use Marcel to deeply inspect the file bytes
        file_stream = File.open(staging_path)
        mime_type = Marcel::MimeType.for(file_stream, name: File.basename(staging_path))
        extracted_meta[:content_type] = mime_type
        file_stream.close

        # --- TYPE-SPECIFIC METADATA ---
        if mime_type.start_with?('image/')
          extract_image_metadata(staging_path, extracted_meta)
          # 🚀 NEW: Extract all visible text
          extract_text_from_image(staging_path, extracted_meta)
        elsif mime_type == 'application/pdf'
          extract_pdf_metadata(staging_path, extracted_meta)
        elsif mime_type.start_with?('video/')
          extracted_meta[:format] = 'Video Media'
        end

        # --- DYNAMIC STORAGE PATH ---
        safe_ext = Marcel::Magic.new(mime_type)&.extensions&.first || "bin"
        # 🚀 FIX: Path now includes version number to prevent overwriting
        file_path = "#{asset.uuid}/v#{version.version_number}_#{SecureRandom.hex(4)}.#{safe_ext}"

        # --- EXECUTE STORAGE ---
        File.open(staging_path, 'rb') do |file|
          storage.store(file, file_path)
        end

        File.delete(staging_path)
      else
        file_path = "#{asset.uuid}/v#{version.version_number}_mock.bin"
        storage.store(StringIO.new("Mock data"), file_path)
        extracted_meta[:content_type] = 'application/octet-stream'
      end

      # --- SAVE & MERGE ---
      current_props = version.properties.is_a?(Hash) ? version.properties : {}

      # 🚀 ARCHITECTURE FIX: Save the physical properties to the VERSION
      version.update!(
        properties: current_props.merge(extracted_meta).merge(
          storage_path: file_path,
          processed_at: Time.current
        )
      )

      # Mark the PARENT as ready
      asset.update!(status: 'ready')

      AssetWorkflowTriggerWorker.perform_async(asset.id, 'on_upload') if defined?(AssetWorkflowTriggerWorker)

      Rails.logger.info "✅ AssetVersion #{version.id} processed and stored as #{file_path}"

    rescue StandardError => e
      Rails.logger.warn "⚠️ Worker failed for AssetVersion #{version.id}: #{e.message}"
      raise e
    end
  end

  private

  def extract_image_metadata(path, meta)
    require 'mini_magick'
    image = MiniMagick::Image.open(path)

    meta[:width] = image.width
    meta[:height] = image.height
    meta[:aspect_ratio] = (image.width.to_f / image.height).round(2)
    meta[:resolution] = "#{image.width} x #{image.height}"
    meta[:color_space] = image.colorspace

    extract_color_palette(path, meta)

    exif = image.exif
    if exif.any?
      meta[:camera_make] = exif['Make']&.strip
      meta[:camera_model] = exif['Model']&.strip
      meta[:software] = exif['Software']&.strip
    end
  rescue StandardError => e
    Rails.logger.error "Minor error: Image metadata extraction failed: #{e.message}"
    meta[:image_analysis_status] = "failed"
  end

  def extract_color_palette(path, meta)
    # Pass 'false' (whiny: false) to prevent the argument error in newer MiniMagick versions
    output = MiniMagick::Tool::Convert.new(false) do |convert|
      convert << path
      convert << "-format" << "%c"
      convert << "-colors" << "5"
      convert << "-depth" << "8"
      convert << "histogram:info:-"
    end

    hex_codes = output.scan(/#[0-9A-Fa-f]{6}/).uniq
    meta[:color_palette] = hex_codes
  rescue StandardError => e
    Rails.logger.error "Color palette extraction failed: #{e.message}"
    meta[:color_palette] = []
  end

  # 🚀 NEW: OCR Text Extraction Block
  def extract_text_from_image(path, meta)
    require 'rtesseract'

    # Process the image with Tesseract to find readable characters
    image = RTesseract.new(path)
    extracted_text = image.to_s.strip

    if extracted_text.present?
      # Store the text block in the metadata for semantic search later
      meta[:extracted_text] = extracted_text
      Rails.logger.info "📝 OCR Extracted #{extracted_text.length} characters."
    end
  rescue StandardError => e
    Rails.logger.error "OCR extraction failed: #{e.message}"
  end

  def extract_pdf_metadata(path, meta)
    meta[:document_type] = 'PDF'
  end
end