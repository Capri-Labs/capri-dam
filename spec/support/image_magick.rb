# frozen_string_literal: true

# Feature detection for the ImageMagick CLI that the image pipeline depends on.
#
# WHY THIS EXISTS
# ---------------
# `mini_magick` 5.x drives the ImageMagick *7* `magick` binary; the ImageMagick 6
# packages that most LTS distributions still ship only provide `convert`, which
# the gem will not use. Specs that build their own source image previously shelled
# out to `magick` with both streams sent to /dev/null and the exit status
# discarded, so on a machine without ImageMagick 7 the fixture was simply never
# written. The specs then failed far away from the cause, as 404s from the
# delivery endpoint and NoMethodError on a nil derivative, which says nothing
# about the missing binary.
#
# Encoding AVIF additionally needs a libheif delegate compiled in, which is a
# separate capability from "ImageMagick 7 is installed".
module ImageMagickSupport
  module_function

  # @return [Boolean] whether the ImageMagick 7 `magick` binary is on PATH
  def available?
    return @available if defined?(@available)

    @available = system("magick", "-version", out: File::NULL, err: File::NULL) || false
  end

  # @return [Boolean] whether this ImageMagick can also *write* AVIF
  def avif_capable?
    return @avif_capable if defined?(@avif_capable)

    @avif_capable = available? && begin
      formats = `magick -list format 2>/dev/null`
      # The delegate table marks writable formats with a "w" in the mode column.
      formats.lines.grep(/^\s*AVIF\b/).any? { |line| line.split[2].to_s.include?("w") }
    rescue StandardError
      false
    end
  end

  # @return [String, nil] a message explaining why these specs cannot run
  def skip_reason
    return "ImageMagick 7 (`magick`) is not installed" unless available?
    return "This ImageMagick cannot encode AVIF (no libheif delegate)" unless avif_capable?

    nil
  end

  # Build a source image, failing loudly rather than leaving a missing file
  # behind for a later expectation to trip over.
  #
  # A noisy gradient rather than a flat colour: flat images compress
  # unrealistically well in every format and would prove nothing about whether
  # the encoder actually ran.
  #
  # @return [String] the path written
  def write_source!(path, geometry: "800x600", quality: 92)
    FileUtils.mkdir_p(File.dirname(path))

    ok = system("magick", "-size", geometry, "plasma:fractal", "-quality", quality.to_s,
                path.to_s, out: File::NULL, err: File::NULL)

    unless ok && File.exist?(path) && File.size(path).positive?
      raise "Could not create the ImageMagick source fixture at #{path}. #{skip_reason}"
    end

    path.to_s
  end
end

RSpec.configure do |config|
  # Opt in with `requires_image_magick: true`.
  config.before(:each, :requires_image_magick) do
    reason = ImageMagickSupport.skip_reason
    skip(reason) if reason
  end
end
