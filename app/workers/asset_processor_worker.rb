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
#    - Full embedded metadata (EXIF, IPTC, XMP, Photoshop, ICC) via ExifTool
#      when the binary is available, promoting descriptive fields such as
#      author, copyright, keywords, and lens to top-level keys.
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
require "open3"

class AssetProcessorWorker
  include Sidekiq::Worker
  sidekiq_options queue: "ingest", retry: 3

  # MIME types that browsers can render natively in an +<img>+ tag.  Any image
  # asset whose MIME type is NOT in this list (e.g. Photoshop PSD, TIFF, HEIC)
  # gets a flattened PNG preview generated so the UI can still display it.
  WEB_RENDERABLE_MIME_TYPES = %w[
    image/jpeg
    image/jpg
    image/pjpeg
    image/png
    image/gif
    image/webp
    image/svg+xml
    image/avif
  ].freeze

  # ExifTool metadata groups that are noise for a DAM (the tool itself, the
  # source path, and duplicated File-system attributes we already capture) and
  # are therefore dropped from the stored +embedded_metadata+ hash.
  EXIFTOOL_SKIP_GROUPS = %w[SourceFile ExifTool File Composite APP14].freeze

  # High-value descriptive fields promoted to top-level metadata keys so the
  # asset viewer and search can use them directly.  Each entry lists the
  # ExifTool +Group:Tag+ candidates in priority order; the first non-blank match
  # wins.  This captures the IPTC / XMP / Photoshop descriptive metadata (author,
  # copyright, lens, colour mode, document IDs, …) that MiniMagick's EXIF-only
  # reader silently drops.
  EXIFTOOL_DESCRIPTIVE_MAP = {
    creator: %w[XMP:Creator IPTC:By-line EXIF:Artist],
    copyright: %w[XMP:Rights IPTC:CopyrightNotice EXIF:Copyright],
    description: %w[XMP:Description IPTC:Caption-Abstract EXIF:ImageDescription],
    headline: %w[XMP:Headline IPTC:Headline],
    title: %w[XMP:Title IPTC:ObjectName],
    keywords: %w[XMP:Subject IPTC:Keywords],
    lens: %w[XMP:Lens EXIF:LensModel Composite:LensID],
    camera_make: %w[EXIF:Make],
    camera_model: %w[EXIF:Model],
    date_taken: %w[EXIF:DateTimeOriginal XMP:CreateDate EXIF:CreateDate],
    color_mode: %w[XMP:ColorMode],
    icc_profile: %w[ICC_Profile:ProfileDescription XMP:ICCProfileName],
    document_id: %w[XMP:DocumentID],
    instance_id: %w[XMP:InstanceID],
    software: %w[EXIF:Software XMP:CreatorTool],
  }.freeze

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

          # Photoshop / TIFF / HEIC and other non-web formats cannot be shown in
          # a browser <img> tag, so render a flattened PNG preview and stage it.
          unless WEB_RENDERABLE_MIME_TYPES.include?(mime_type)
            generate_web_preview(staging_path, asset, version, storage, extracted_meta)
          end
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
  # In addition to the basic dimensions this captures the *full* EXIF hash under
  # +:exif_data+ (surfaced by the asset viewer) and a set of extended technical
  # properties (DPI, bit depth, channels, compression, ICC profile, layer count,
  # orientation) so formats rich in metadata such as PSD and TIFF are not
  # reduced to just a handful of fields.
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
    if exif.respond_to?(:any?) && exif.any?
      cleaned = clean_exif(exif)
      meta[:exif_data]    = cleaned if cleaned.any?
      meta[:camera_make]  = exif["Make"]&.strip
      meta[:camera_model] = exif["Model"]&.strip
      meta[:software]     = exif["Software"]&.strip
    end

    extract_extended_image_properties(image, meta)
    extract_embedded_metadata(path, meta)
  rescue StandardError => e
    Rails.logger.error "Minor error: Image metadata extraction failed: #{e.message}"
    meta[:image_analysis_status] = "failed"
  end

  # Strips whitespace from EXIF values and drops blank entries so the stored
  # +exif_data+ hash is clean for display.
  #
  # @param exif [Hash]
  # @return [Hash]
  def clean_exif(exif)
    exif.each_with_object({}) do |(key, value), acc|
      next if key.blank?

      cleaned = value.is_a?(String) ? value.strip : value
      acc[key.to_s] = cleaned unless cleaned.nil? || cleaned == ""
    end
  end

  # Pulls extended technical properties from an image using ImageMagick's
  # +identify+ output.  Every lookup is defensive: a format that does not expose
  # a given property simply omits that key rather than aborting extraction.
  #
  # @param image [MiniMagick::Image]
  # @param meta [Hash] mutable metadata hash to populate
  # @return [void]
  def extract_extended_image_properties(image, meta)
    meta[:format]      = safe_image_attr { image.type }
    meta[:bit_depth]   = safe_image_attr { image["%[bit-depth]"].presence || image["%z"].presence }
    meta[:channels]    = safe_image_attr { image["%[channels]"].presence }
    meta[:compression] = safe_image_attr { image["%C"].presence }
    meta[:orientation] = safe_image_attr { image["%[orientation]"].presence }

    density = safe_image_attr { image["%x x %y"].presence }
    meta[:dpi] = density if density.present? && density != "0 x 0"

    icc = safe_image_attr { image["%[profile:icc]"].presence || image["%[profiles]"].presence }
    meta[:color_profile] = icc if icc.present?

    layers = safe_image_attr { image.layers&.size }
    meta[:layer_count] = layers if layers.to_i > 1

    # Drop any properties that resolved to nil so the stored hash stays tidy.
    meta.reject! { |_k, v| v.nil? }
  end

  # Runs the given block, returning +nil+ (or the supplied default) when the
  # underlying ImageMagick lookup is unavailable or raises.
  #
  # @return [Object, nil]
  def safe_image_attr(default = nil)
    yield
  rescue StandardError
    default
  end

  # Extracts the *full* set of embedded metadata (EXIF, IPTC, XMP, Photoshop and
  # ICC profile fields) using ExifTool and merges it into +meta+.
  #
  # MiniMagick's +Image#exif+ only surfaces the ~20 tags of the EXIF group,
  # silently dropping the IPTC / XMP / Photoshop namespaces that hold the most
  # useful descriptive metadata for a DAM — author, copyright, keywords, lens,
  # colour mode, document IDs and so on.  ExifTool reads all of them, so a file
  # that previously yielded ~20 fields now yields well over a hundred.
  #
  # The complete, group-namespaced payload is stored under
  # +:embedded_metadata+, the flat EXIF group is folded into +:exif_data+ (so
  # the existing viewer panel keeps working), and a curated set of descriptive
  # fields (see {EXIFTOOL_DESCRIPTIVE_MAP}) is promoted to top-level keys.
  #
  # Non-fatal and gracefully degrading: when the +exiftool+ binary is not
  # installed (or errors) the method simply returns and the asset keeps the
  # MiniMagick-derived EXIF data.
  #
  # @param path [String] absolute path to the image file
  # @param meta [Hash]   mutable metadata hash to populate
  # @return [void]
  def extract_embedded_metadata(path, meta)
    return unless exiftool_available?

    out, _err, status = Open3.capture3(
      "exiftool", "-json", "-G0", "-struct", "-api", "largefilesupport=1", path
    )
    return unless status.success?

    raw = JSON.parse(out).first
    return unless raw.is_a?(Hash)

    grouped = Hash.new { |hash, key| hash[key] = {} }
    raw.each do |key, value|
      group, tag = key.split(":", 2)
      next if tag.nil? || EXIFTOOL_SKIP_GROUPS.include?(group)
      next if binary_placeholder?(value)

      grouped[group][tag] = value
    end
    return if grouped.empty?

    meta[:embedded_metadata] = grouped
    meta[:metadata_field_count] = grouped.values.sum(&:size)

    exif_group = grouped["EXIF"]
    if exif_group.present?
      existing = meta[:exif_data].is_a?(Hash) ? meta[:exif_data] : {}
      meta[:exif_data] = existing.merge(exif_group)
    end

    apply_descriptive_metadata(raw, meta)
  rescue StandardError => e
    Rails.logger.error "Minor error: ExifTool metadata extraction failed: #{e.message}"
  end

  # Promotes the first non-blank descriptive candidate for each mapped field
  # (creator, copyright, lens, …) onto +meta+.
  #
  # @param raw  [Hash] ExifTool's flat +Group:Tag => value+ output
  # @param meta [Hash] mutable metadata hash to populate
  # @return [void]
  def apply_descriptive_metadata(raw, meta)
    EXIFTOOL_DESCRIPTIVE_MAP.each do |field, candidates|
      candidates.each do |candidate|
        value = raw[candidate]
        next if value.nil? || binary_placeholder?(value)
        next if value.is_a?(String) && value.strip.empty?
        next if value.is_a?(Array) && value.empty?

        meta[field] = value.is_a?(String) ? value.strip : value
        break
      end
    end
  end

  # @return [Boolean] true when the value is an ExifTool binary-data placeholder
  #   string (e.g. embedded thumbnails) that should not be stored.
  def binary_placeholder?(value)
    value.is_a?(String) && value.start_with?("(Binary data")
  end

  # @return [Boolean] whether the +exiftool+ binary is on +PATH+.  Memoised so
  #   the availability probe runs at most once per worker instance.
  def exiftool_available?
    return @exiftool_available unless @exiftool_available.nil?

    @exiftool_available = system("which", "exiftool", out: File::NULL, err: File::NULL) || false
  end

  # Generates a flattened, web-renderable PNG preview for image formats that
  # browsers cannot display natively (PSD, TIFF, HEIC, …) and stores it via the
  # active storage backend.  Populates +:preview_storage_path+ and
  # +:preview_content_type+ so the API can serve the preview separately from the
  # original binary.
  #
  # Non-fatal: any failure is logged and the asset still processes without a
  # preview.
  #
  # @param source_path [String]
  # @param asset [Asset]
  # @param version [AssetVersion]
  # @param storage [Object] storage adapter responding to +store+
  # @param meta [Hash] mutable metadata hash to populate
  # @return [void]
  def generate_web_preview(source_path, asset, version, storage, meta)
    require "mini_magick"
    preview_tmp = Rails.root.join("tmp", "preview_#{SecureRandom.hex(8)}.png").to_s

    MiniMagick::Tool::Convert.new(false) do |convert|
      convert.background "white"
      convert << "#{source_path}[0]"
      convert.flatten
      convert << preview_tmp
    end

    return unless File.exist?(preview_tmp)

    preview_path = "#{asset.uuid}/v#{version.version_number}_preview_#{SecureRandom.hex(4)}.png"
    File.open(preview_tmp, "rb") { |file| storage.store(file, preview_path) }

    meta[:preview_storage_path] = preview_path
    meta[:preview_content_type] = "image/png"
    Rails.logger.info "🖼️ Generated web preview for AssetVersion #{version.id} at #{preview_path}"
  rescue StandardError => e
    Rails.logger.error "Web preview generation failed: #{e.message}"
  ensure
    File.delete(preview_tmp) if preview_tmp && File.exist?(preview_tmp)
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
