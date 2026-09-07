module ImageDelivery
  # Decides which image format a delivery request should actually be answered
  # with.
  #
  # WHY THIS IS NOT JUST "USE AVIF IF THE BROWSER SAYS IT CAN"
  # ---------------------------------------------------------
  # Three things have to agree before a request is answered in a modern format,
  # and each of them can veto:
  #
  # 1. *The administrator* enabled the format. The allow-list already shipped on
  #    {CdnConfiguration} (+settings["image_optimizer_formats"]+) previously only
  #    described what an edge CDN was permitted to do; it now also governs what
  #    this application will produce, so one switch means one behaviour whether
  #    or not a CDN sits in front. With no active CDN configuration nothing is
  #    transcoded — the feature is off until somebody turns it on.
  #
  # 2. *The client* said it could decode it. Safari and older Chrome/Firefox
  #    advertise WebP but not AVIF, and a browser sent an image format it cannot
  #    decode shows a broken image, not a slightly larger one. An explicit
  #    +?format=+ is honoured without consulting +Accept+ (a build pipeline
  #    fetching AVIF is not a browser and need not pretend to be one), but it is
  #    still subject to the administrator's allow-list.
  #
  # 3. *The source* is worth transcoding. Only still raster photographs are:
  #    re-encoding an SVG destroys the reason it is a vector, and a GIF may be
  #    animated, which a single-frame AVIF would silently truncate to its first
  #    frame.
  #
  # Preference is AVIF before WebP because it is materially smaller at equal
  # quality; whether the result is *actually* smaller for this particular image
  # is not decided here but in {Derivative}, which keeps the original when the
  # transcode fails to pay for itself.
  class FormatNegotiator
    FORMATS = {
      "avif" => "image/avif",
      "webp" => "image/webp",
    }.freeze

    # Ordered by preference, best first.
    PREFERENCE = %w[avif webp].freeze

    # Formats worth re-encoding. Deliberately excludes SVG (vector), GIF
    # (possibly animated) and the modern formats themselves (already optimal).
    TRANSCODABLE_SOURCE_TYPES = %w[
      image/jpeg
      image/jpg
      image/pjpeg
      image/png
    ].freeze

    Result = Struct.new(:format, :content_type, keyword_init: true)

    # @param source_content_type [String] MIME type of the stored original
    # @param accept_header [String, nil] the request's +Accept+ header
    # @param requested_format [String, nil] an explicit +?format=+ override
    def initialize(source_content_type:, accept_header: nil, requested_format: nil)
      @source_content_type = source_content_type.to_s.downcase.split(";").first.to_s.strip
      @accept_header = accept_header.to_s.downcase
      @requested_format = requested_format.to_s.downcase.strip
    end

    # @return [Result, nil] nil means "serve the original untouched"
    def call
      return nil unless transcodable_source?

      chosen = @requested_format.present? ? explicit_choice : negotiated_choice
      return nil if chosen.blank?

      Result.new(format: chosen, content_type: FORMATS.fetch(chosen))
    end

    # Formats the administrator has switched on, as configured on the active
    # CDN configuration.
    #
    # @return [Array<String>]
    def self.enabled_formats
      config = CdnConfiguration.find_by(is_active: true)
      return [] if config.blank?

      settings = config.settings
      return [] unless settings.is_a?(Hash)

      Array(settings["image_optimizer_formats"])
        .map { |f| f.to_s.downcase }
        .select { |f| FORMATS.key?(f) }
    rescue StandardError => e
      # A delivery request must never fail because the CDN settings could not
      # be decrypted or parsed; it just means no transcoding.
      Rails.logger.warn("[ImageDelivery] could not read optimizer formats: #{e.message}")
      []
    end

    private

    def transcodable_source?
      TRANSCODABLE_SOURCE_TYPES.include?(@source_content_type)
    end

    def enabled
      @enabled ||= self.class.enabled_formats
    end

    # An explicit format is honoured without consulting Accept, but never
    # outside the administrator's allow-list.
    def explicit_choice
      return nil unless FORMATS.key?(@requested_format)
      return nil unless enabled.include?(@requested_format)

      @requested_format
    end

    def negotiated_choice
      PREFERENCE.find { |format| enabled.include?(format) && accepts?(format) }
    end

    # Only an explicit +image/avif+ / +image/webp+ counts. A wildcard +image/*+
    # (or +*/*+, which every browser sends) is not evidence that the client can
    # decode a format that did not exist when it was written.
    def accepts?(format)
      @accept_header.include?(FORMATS.fetch(format))
    end
  end
end
