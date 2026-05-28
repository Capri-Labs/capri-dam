require 'digest'

class AssetProcessorWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'ingest', retry: 3

  # Safety net for complete failures
  sidekiq_retries_exhausted do |msg, exception|
    asset_id = msg['args'].first
    staging_path = msg['args'][1]

    asset = Asset.find_by(id: asset_id)
    asset&.update!(status: 'failed')

    File.delete(staging_path) if staging_path && File.exist?(staging_path)
    Rails.logger.error "💥 Asset #{asset_id} permanently failed: #{exception.message}"
  end

  def perform(asset_id, staging_path = nil)
    asset = Asset.find_by(id: asset_id)
    return unless asset

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

        # Use Marcel (Rails native) to deeply inspect the file bytes, ignoring fake extensions
        file_stream = File.open(staging_path)
        mime_type = Marcel::MimeType.for(file_stream, name: File.basename(staging_path))
        extracted_meta[:content_type] = mime_type
        file_stream.close

        # --- TYPE-SPECIFIC METADATA ---
        if mime_type.start_with?('image/')
          extract_image_metadata(staging_path, extracted_meta)
        elsif mime_type == 'application/pdf'
          extract_pdf_metadata(staging_path, extracted_meta)
        elsif mime_type.start_with?('video/')
          extracted_meta[:format] = 'Video Media' # Placeholder for FFmpeg extraction
        end

        # --- DYNAMIC STORAGE PATH ---
        # Get the safest extension based on the actual MIME type
        safe_ext = Marcel::Magic.new(mime_type)&.extensions&.first || "bin"
        file_path = "#{asset.uuid}/original.#{safe_ext}"

        # --- EXECUTE STORAGE ---
        File.open(staging_path, 'rb') do |file|
          storage.store(file, file_path)
        end

        File.delete(staging_path) # Clean up temp file
      else
        # Mock logic for tests
        file_path = "#{asset.uuid}/original.bin"
        storage.store(StringIO.new("Mock data"), file_path)
        extracted_meta[:content_type] = 'application/octet-stream'
      end

      # --- SAVE & MERGE ---
      # Safely handle the existing properties hash
      current_props = asset.properties.is_a?(Hash) ? asset.properties : {}

      asset.update!(
        status: 'ready',
        # We merge the original properties (like original_filename) with our deep extraction
        properties: current_props.merge(extracted_meta).merge(
          storage_path: file_path,
          processed_at: Time.current
        )
      )
      # Announce to the event stream that a new asset was just ingested
      AssetWorkflowTriggerWorker.perform_async(asset.id, 'on_upload')

      Rails.logger.info "✅ Asset #{asset.uuid} processed and stored as #{file_path}"

    rescue StandardError => e
      Rails.logger.warn "⚠️ Worker failed for Asset #{asset.uuid}: #{e.message}"
      raise e
    end
  end

  private

  def extract_image_metadata(path, meta)
    # Using MiniMagick (standard in Rails ActiveStorage) to read image headers safely
    require 'mini_magick'

    image = MiniMagick::Image.open(path)

    meta[:width] = image.width
    meta[:height] = image.height
    meta[:aspect_ratio] = (image.width.to_f / image.height).round(2)
    meta[:resolution] = "#{image.width} x #{image.height}"
    meta[:color_space] = image.colorspace

    # Extract EXIF data if the photographer left it in the file
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

  def extract_pdf_metadata(path, meta)
    # If you add `gem 'pdf-reader'` to your Gemfile in the future, you can uncomment this:
    # require 'pdf-reader'
    # reader = PDF::Reader.new(path)
    # meta[:page_count] = reader.page_count
    # meta[:pdf_version] = reader.pdf_version
    meta[:document_type] = 'PDF'
  rescue StandardError
    # Silently pass if gem is missing
  end
end