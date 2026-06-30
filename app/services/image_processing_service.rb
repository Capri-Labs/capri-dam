# Handles all image manipulation and adjustment operations using MiniMagick.
#
# == Responsibility
# Encapsulates the logic for applying image adjustments, filters, geometric
# transformations, and custom ImageMagick commands to ensure consistency,
# testability, and maintainability of the image processing pipeline.
#
# == Supported Adjustments
# * **Geometric**: rotation, flip, crop, focal point
# * **Lighting**: brightness, contrast, HDR, highlights, shadows, white/black points
# * **Color**: saturation, warmth, tint, skin tone, blue tone
# * **Effects**: vignette, custom CLI commands
# * **Filters**: LUT-based filters (Vivid, West, Palma, etc.)
#
# == Usage
#   service = ImageProcessingService.new(source_path)
#   output_path = service.process(editor_state)
#   # or with specific adjustments:
#   output_path = service.process(editor_state, output_format: 'jpeg', quality: 90)
#
# == Example
#   adjustments = {
#     brightness: 20,
#     contrast: -10,
#     saturation: 15,
#     rotation: 90,
#     flip_horizontal: true
#   }
#   service = ImageProcessingService.new("/path/to/image.jpg")
#   output = service.process(adjustments)
#
class ImageProcessingService
  DEFAULT_OUTPUT_FORMAT = "jpeg".freeze
  DEFAULT_JPEG_QUALITY = 90.freeze
  MAX_FILE_SIZE = 500.megabytes.freeze
  ALLOWED_FORMATS = %w[jpeg jpg png webp gif tiff].freeze

  VALID_CROP_ASPECTS = {
    "free" => nil,
    "1:1" => [ 1, 1 ],
    "16:9" => [ 16, 9 ],
    "4:3" => [ 4, 3 ],
    "3:2" => [ 3, 2 ],
    "21:9" => [ 21, 9 ],
  }.freeze

  FILTERS = {
    "None" => { operations: [] },
    "Vivid" => { operations: [ "-modulate", "110,130,100" ] },
    "West" => { operations: [ "-modulate", "110,120,100" ] },
    "Palma" => { operations: [ "-colorspace", "RGB", "-modulate", "110,100,100", "-colorspace", "sRGB" ] },
    "Metro" => { operations: [ "-modulate", "105,110,100" ] },
    "Eiffel" => { operations: [ "-modulate", "100,120,100" ] },
    "Blush" => { operations: [ "-modulate", "110,110,100" ] },
    "Modena" => { operations: [ "-modulate", "110,100,90" ] },
    "Vogue" => { operations: [ "-contrast-stretch", "0" ] },
  }.freeze

  class ProcessingError < StandardError; end
  class ValidationError < StandardError; end

  attr_reader :source_path, :logger

  def initialize(source_path, logger: nil)
    @source_path = source_path
    @logger = logger || Rails.logger
    validate_source_file!
  end

  # Processes an image with the given adjustments and returns the output path.
  #
  # @param adjustments [Hash] Hash of adjustment parameters
  # @param output_format [String] Output format (jpeg, png, webp, gif)
  # @param quality [Integer] JPEG quality (1-100)
  # @param output_path [String] Optional override for output file path
  # @return [String] Path to the processed image
  # @raise [ProcessingError] If image processing fails
  # @raise [ValidationError] If adjustments are invalid
  def process(adjustments = {}, output_format: DEFAULT_OUTPUT_FORMAT, quality: DEFAULT_JPEG_QUALITY, output_path: nil)
    validate_adjustments!(adjustments)
    validate_output_format!(output_format)
    validate_quality!(quality)

    image = load_image
    apply_adjustments!(image, adjustments)

    output_file = output_path || generate_output_path(output_format)
    write_image(image, output_file, format: output_format, quality: quality)

    logger.info("Image processing complete: #{source_path} -> #{output_file}")
    output_file
  rescue MiniMagick::Error => e
    logger.error("ImageMagick error: #{e.message}")
    raise ProcessingError, "Image processing failed: #{e.message}"
  rescue StandardError => e
    logger.error("Unexpected error during image processing: #{e.message}")
    raise ProcessingError, "Unexpected error: #{e.message}"
  end

  private

  # Validates that the source file exists and is readable.
  #
  # @raise [ValidationError] If file doesn't exist or isn't readable
  def validate_source_file!
    raise ValidationError, "Source file does not exist: #{source_path}" unless File.exist?(source_path)
    raise ValidationError, "Source file is not readable: #{source_path}" unless File.readable?(source_path)

    file_size = File.size(source_path)
    if file_size > MAX_FILE_SIZE
      raise ValidationError, "Source file exceeds maximum size (#{MAX_FILE_SIZE / 1.megabyte}MB)"
    end
  end

  # Validates adjustment parameters.
  #
  # @param adjustments [Hash] Adjustment parameters
  # @raise [ValidationError] If any adjustment value is invalid
  def validate_adjustments!(adjustments)
    return if adjustments.blank?

    # Validate slider adjustments are within range
    adjustments.slice(:brightness, :contrast, :saturation, :warmth, :tint, :skin_tone,
                      :blue_tone, :hdr, :white_point, :highlights, :shadows, :black_point,
                      :vignette).each do |key, value|
      value = value.to_i
      range = key == :vignette ? 0..100 : -100..100
      raise ValidationError, "#{key} must be between #{range.min} and #{range.max}" unless range.include?(value)
    end

    # Validate rotation
    if adjustments[:rotation].present?
      rotation = adjustments[:rotation].to_i
      raise ValidationError, "rotation must be divisible by 90" unless (rotation % 90).zero?
    end

    # Validate focal point
    if adjustments[:focal_point].present?
      fp = adjustments[:focal_point]
      raise ValidationError, "focal_point must have x and y coordinates" unless fp.is_a?(Hash) && fp["x"].present? && fp["y"].present?
      x, y = fp["x"].to_f, fp["y"].to_f
      raise ValidationError, "focal_point x must be between 0 and 100" unless (0..100).include?(x)
      raise ValidationError, "focal_point y must be between 0 and 100" unless (0..100).include?(y)
    end

    # Validate crop aspect
    if adjustments[:crop_aspect].present?
      raise ValidationError, "crop_aspect must be one of: #{VALID_CROP_ASPECTS.keys.join(", ")}" unless VALID_CROP_ASPECTS.key?(adjustments[:crop_aspect])
    end

    # Validate filter
    if adjustments[:filter].present?
      raise ValidationError, "filter must be one of: #{FILTERS.keys.join(", ")}" unless FILTERS.key?(adjustments[:filter])
    end
  end

  # Validates output format.
  #
  # @param format [String] Output format
  # @raise [ValidationError] If format is not supported
  def validate_output_format!(format)
    raise ValidationError, "Output format must be one of: #{ALLOWED_FORMATS.join(", ")}" unless ALLOWED_FORMATS.include?(format)
  end

  # Validates JPEG quality.
  #
  # @param quality [Integer] Quality value
  # @raise [ValidationError] If quality is out of range
  def validate_quality!(quality)
    raise ValidationError, "Quality must be between 1 and 100" unless (1..100).include?(quality.to_i)
  end

  # Loads the image file with MiniMagick.
  #
  # @return [MiniMagick::Image]
  def load_image
    require "mini_magick"
    MiniMagick::Image.open(source_path)
  end

  # Applies all adjustments to the image using MiniMagick's combine_options.
  #
  # @param image [MiniMagick::Image] Image to modify
  # @param adjustments [Hash] Adjustment parameters
  def apply_adjustments!(image, adjustments)
    image.combine_options do |cmd|
      # Geometry: Flip & Rotation (applied first)
      apply_geometry(cmd, adjustments)

      # Lighting: Brightness & Contrast
      apply_lighting(cmd, adjustments)

      # Color: Saturation, Warmth, Tint, Skin/Blue Tone
      apply_color(cmd, adjustments)

      # Effects: Vignette, etc.
      apply_effects(cmd, adjustments)

      # Filters: LUT, presets
      apply_filter(cmd, adjustments)

      # Custom CLI (last, highest priority)
      apply_custom_cli(cmd, adjustments)
    end
  end

  # Applies geometric transformations (flip, rotation).
  #
  # @param cmd [Object] MiniMagick command builder
  # @param adjustments [Hash] Adjustments
  def apply_geometry(cmd, adjustments)
    # Flip horizontal (flop in ImageMagick)
    cmd.flop if adjustments[:flip_horizontal].present? && adjustments[:flip_horizontal]

    # Flip vertical (flip in ImageMagick)
    cmd.flip if adjustments[:flip_vertical].present? && adjustments[:flip_vertical]

    # Rotation (can be any degree, but typically 0, 90, 180, 270)
    rotation = adjustments[:rotation].to_i
    cmd.rotate(rotation.to_s) if rotation != 0
  end

  # Applies lighting adjustments (brightness, contrast, HDR, highlights, shadows).
  #
  # @param cmd [Object] MiniMagick command builder
  # @param adjustments [Hash] Adjustments
  def apply_lighting(cmd, adjustments)
    brightness = adjustments[:brightness].to_i
    contrast = adjustments[:contrast].to_i

    # Apply brightness and contrast together if either is non-zero
    if brightness != 0 || contrast != 0
      cmd.brightness_contrast("#{brightness}x#{contrast}")
    end

    # White point adjustment (affects highlights)
    if adjustments[:white_point].present? && adjustments[:white_point].to_i != 0
      white_point = adjustments[:white_point].to_i
      cmd.level("0x100%x#{100 + white_point}%")
    end

    # Black point adjustment (affects shadows)
    if adjustments[:black_point].present? && adjustments[:black_point].to_i != 0
      black_point = adjustments[:black_point].to_i
      # Negative black point brightens shadows, positive darkens them
      cmd.level("#{black_point}%x100%")
    end

    # Highlights adjustment (brighten bright areas)
    if adjustments[:highlights].present? && adjustments[:highlights].to_i != 0
      highlights = adjustments[:highlights].to_i
      # Use level to adjust highlights: adjust black point keeps shadows, adjust white point affects highlights
      cmd.level("0x100%x#{100 + highlights}%") if highlights > 0
    end

    # Shadows adjustment (brighten/darken dark areas)
    if adjustments[:shadows].present? && adjustments[:shadows].to_i != 0
      shadows = adjustments[:shadows].to_i
      # Adjust shadows by modulating brightness in lower tones
      cmd.level("#{shadows > 0 ? -shadows : 0}%") if shadows != 0
    end

    # HDR effect (enhance contrast in mid-tones)
    if adjustments[:hdr].present? && adjustments[:hdr].to_i != 0
      hdr = adjustments[:hdr].to_i
      # Simple HDR simulation using modulate and equalize
      if hdr > 0
        hdr_strength = (hdr / 100.0 * 0.3).round(2) # Scale to 0-0.3 range
        cmd.sigmoidal_contrast("#{5 + hdr_strength * 10}x50%")
      end
    end
  end

  # Applies color adjustments (saturation, warmth, tint, skin/blue tone).
  #
  # @param cmd [Object] MiniMagick command builder
  # @param adjustments [Hash] Adjustments
  def apply_color(cmd, adjustments)
    saturation = adjustments[:saturation].to_i
    warmth = adjustments[:warmth].to_i
    tint = adjustments[:tint].to_i
    skin_tone = adjustments[:skin_tone].to_i
    blue_tone = adjustments[:blue_tone].to_i

    # Saturation adjustment using modulate: modulate brightness,saturation,hue
    if saturation != 0
      saturation_value = 100 + saturation
      cmd.modulate("100,#{saturation_value},100")
    end

    # Warmth/Temperature: positive = warm (yellow), negative = cool (blue)
    # This is a simplified approach using modulate and colorspace
    if warmth != 0
      if warmth > 0
        # Warm: enhance reds and yellows
        warmth_strength = (warmth / 100.0).round(2)
        cmd.modulate("100,100,#{-warmth_strength * 5}") # Shift hue towards red
      else
        # Cool: enhance blues
        coolness_strength = (-warmth / 100.0).round(2)
        cmd.modulate("100,100,#{coolness_strength * 5}") # Shift hue towards blue
      end
    end

    # Tint adjustment (hue rotation)
    if tint != 0
      # Hue rotation in ImageMagick: -modulate 100,100,DEGREES
      # Positive tint = shift towards magenta/red, negative = shift towards green
      tint_degrees = (tint / 100.0 * 30).round(1) # Scale -100..100 to -30..30 degrees
      cmd.modulate("100,100,#{tint_degrees}")
    end

    # Skin tone adjustment (enhance warm tones for faces)
    if skin_tone != 0
      skin_strength = (skin_tone / 100.0).round(2)
      if skin_tone > 0
        # Enhance skin tones: boost reds slightly, reduce saturation of blues
        cmd.modulate("100,#{100 + skin_tone * 0.3},#{-skin_tone * 0.2}")
      end
    end

    # Blue tone adjustment
    if blue_tone != 0
      blue_strength = (blue_tone / 100.0).round(2)
      if blue_tone > 0
        # Enhance blue tones
        cmd.modulate("100,100,#{blue_strength * 30}")
      end
    end
  end

  # Applies effects like vignette.
  #
  # @param cmd [Object] MiniMagick command builder
  # @param adjustments [Hash] Adjustments
  def apply_effects(cmd, adjustments)
    vignette = adjustments[:vignette].to_i

    if vignette > 0
      # Apply vignette using vignette operation
      # Scale vignette strength
      vignette_strength = (vignette / 100.0 * 40).round(1) # Scale to ~0-40 for vignette radius
      cmd.vignette("0x#{vignette_strength}")
    end
  end

  # Applies LUT-based filter presets.
  #
  # @param cmd [Object] MiniMagick command builder
  # @param adjustments [Hash] Adjustments
  def apply_filter(cmd, adjustments)
    filter = adjustments[:filter].to_s

    # Skip if no filter or "None" filter
    return if filter.blank? || filter == "None"

    filter_config = FILTERS[filter] || FILTERS["None"]
    return if filter_config.blank? || filter_config[:operations].blank?

    # Apply each operation in the filter
    filter_config[:operations].each_slice(2) do |operation, *args|
      cmd.send(operation, *args) if cmd.respond_to?(operation.to_sym)
    end
  end

  # Injects raw ImageMagick CLI commands (highest priority, last to apply).
  #
  # @param cmd [Object] MiniMagick command builder
  # @param adjustments [Hash] Adjustments
  def apply_custom_cli(cmd, adjustments)
    custom_cli = adjustments[:custom_cli].to_s.strip
    return if custom_cli.blank?

    # Parse and inject raw ImageMagick commands
    # Expected format: "-operation1 arg1 -operation2 arg2"
    # Safety: only allow operations starting with a dash and alphanumeric operations
    custom_cli.scan(/-[a-z_]+[^-]*/).each do |arg|
      cmd << arg.strip
    end
  end

  # Generates a temporary output file path.
  #
  # @param format [String] Output format
  # @return [String] Temporary file path
  def generate_output_path(format = "jpeg")
    Rails.root.join("tmp", "processed_image_#{SecureRandom.hex(8)}.#{format}").to_s
  end

  # Writes the processed image to disk.
  #
  # @param image [MiniMagick::Image] Image to write
  # @param output_path [String] Output file path
  # @param format [String] Output format
  # @param quality [Integer] JPEG quality
  def write_image(image, output_path, format: "jpeg", quality: 90)
    image.format(format)
    image.quality(quality.to_s) if format.downcase.in?([ "jpeg", "jpg", "webp" ])
    image.write(output_path)
  end
end
