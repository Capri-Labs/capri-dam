# frozen_string_literal: true

module Preservation
  # Classifies stored formats by the risk that nothing will be able to open
  # them in ten years' time.
  #
  # WHY THIS IS NOT THE SAME PROBLEM AS FIXITY
  # ------------------------------------------
  # Fixity answers "are the bytes still the bytes". This answers the question
  # that outlives it: "will anything still be able to read them". Those fail
  # independently and the second is the quieter of the two — a perfectly intact
  # FLA, SWF or proprietary camera raw from a discontinued body passes every
  # integrity check ever run against it and is still, in practice, gone. The
  # bytes survived; the software that understood them did not.
  #
  # The registry exists so an archive can see that coming while migration is
  # still cheap, rather than discovering it during the one restore that matters.
  #
  # WHY THE LIST IS CURATED AND NOT DERIVED
  # ---------------------------------------
  # There is no signal inside a file that says its ecosystem is dying. The risk
  # is a fact about the outside world — vendor support, browser removals,
  # whether an open specification exists — so it has to be asserted here and
  # revisited deliberately. The tiers are coarse on purpose: the useful output
  # is "migrate this class of thing", not a false-precision score.
  class FormatRegistry
    # Open specification, multiple independent implementations, no single
    # vendor able to withdraw it. Safe to leave alone.
    LOW = "low"

    # Readable today and likely for years, but controlled by one vendor or
    # dependent on a shrinking implementation base. Worth a normalised access
    # copy alongside the master.
    MEDIUM = "medium"

    # Already unsupported, already removed from mainstream software, or tied to
    # hardware that is no longer made. Migrate now; the tooling still exists.
    HIGH = "high"

    # Keyed by MIME type. +recommendation+ is deliberately phrased as an action
    # rather than a rating, because a risk score nobody knows what to do with
    # gets ignored.
    FORMATS = {
      # --- Preservation-grade: open, documented, widely implemented ---
      "image/jpeg"      => { risk: LOW,    category: "image",    note: "ISO standard; universal support." },
      "image/png"       => { risk: LOW,    category: "image",    note: "W3C/ISO standard; universal support." },
      "image/tiff"      => { risk: LOW,    category: "image",    note: "De-facto archival master format." },
      "image/webp"      => { risk: LOW,    category: "image",    note: "Open, supported by every current browser." },
      "image/avif"      => { risk: LOW,    category: "image",    note: "Open (AV1); broad and growing support." },
      "application/pdf" => { risk: LOW,    category: "document", note: "ISO standard. Prefer PDF/A for masters." },
      "video/mp4"       => { risk: LOW,    category: "video",    note: "Ubiquitous container; check the codec inside." },
      "audio/mpeg"      => { risk: LOW,    category: "audio",    note: "Patents expired; universally decodable." },
      "audio/wav"       => { risk: LOW,    category: "audio",    note: "Uncompressed; the audio archival master." },
      "text/plain"      => { risk: LOW,    category: "document", note: "No decoder required beyond an encoding." },
      "text/csv"        => { risk: LOW,    category: "data",     note: "Plain text; trivially recoverable." },
      "model/gltf+json" => { risk: LOW,    category: "3d",       note: "Khronos open standard." },
      "model/gltf-binary" => { risk: LOW,  category: "3d",       note: "Khronos open standard." },

      # --- Vendor-controlled or narrowing support ---
      "image/vnd.adobe.photoshop" => { risk: MEDIUM, category: "image", note: "Single-vendor format. Keep a TIFF or PNG access copy." },
      "application/postscript"    => { risk: MEDIUM, category: "vector", note: "AI/EPS: vendor-controlled. Export PDF/SVG copies." },
      "image/svg+xml"             => { risk: MEDIUM, category: "vector", note: "Open, but rendering varies; pin a rasterised copy." },
      "video/quicktime"           => { risk: MEDIUM, category: "video",  note: "Container is fine; ProRes inside is vendor-controlled." },
      "image/heic"                => { risk: MEDIUM, category: "image",  note: "Patent-encumbered; support is uneven off-Apple." },
      "image/heif"                => { risk: MEDIUM, category: "image",  note: "Patent-encumbered; support is uneven off-Apple." },
      "application/msword"        => { risk: MEDIUM, category: "document", note: "Legacy binary Office. Convert to OOXML or PDF/A." },
      "application/vnd.ms-excel"  => { risk: MEDIUM, category: "document", note: "Legacy binary Office. Convert to OOXML or PDF/A." },
      "model/vnd.usdz+zip"        => { risk: MEDIUM, category: "3d",     note: "Open-ish but effectively single-vendor tooling." },
      "model/stl"                 => { risk: MEDIUM, category: "3d",     note: "No colour/material; keep source CAD if it exists." },

      # --- Already failing ---
      "application/x-shockwave-flash" => { risk: HIGH, category: "interactive", note: "Player discontinued 2020. No supported runtime exists." },
      "application/vnd.adobe.flash.movie" => { risk: HIGH, category: "interactive", note: "Player discontinued 2020. Migrate to video." },
      "video/x-flv"                   => { risk: HIGH, category: "video",   note: "Flash-era container. Remux to MP4." },
      "audio/x-ms-wma"                => { risk: HIGH, category: "audio",   note: "Abandoned by its vendor. Transcode to WAV/MP3." },
      "video/x-ms-wmv"                => { risk: HIGH, category: "video",   note: "Abandoned by its vendor. Transcode to MP4." },
      "video/x-ms-asf"                => { risk: HIGH, category: "video",   note: "Abandoned by its vendor. Transcode to MP4." },
      "application/vnd.ms-works"      => { risk: HIGH, category: "document", note: "Discontinued 2009. Convert immediately." },
      "image/x-pict"                  => { risk: HIGH, category: "image",   note: "Classic Mac PICT. Almost no modern decoder." },
      "application/x-director"        => { risk: HIGH, category: "interactive", note: "Shockwave. No supported runtime exists." },
      "image/vnd.fpx"                 => { risk: HIGH, category: "image",   note: "FlashPix. Effectively unreadable." },
    }.freeze

    # Formats not in the table are unknown rather than safe. Saying "low" about
    # something nobody has assessed is exactly the mistake this class exists to
    # prevent, so the default is a prompt to look.
    UNKNOWN = { risk: MEDIUM, category: "unknown", note: "Not assessed. Confirm a supported decoder exists." }.freeze

    class << self
      # @param content_type [String, nil]
      # @return [Hash] +:risk+, +:category+, +:note+
      def classify(content_type)
        return UNKNOWN if content_type.blank?

        FORMATS.fetch(content_type.to_s.downcase.split(";").first.to_s.strip, UNKNOWN)
      end

      # @return [Boolean]
      def at_risk?(content_type)
        classify(content_type)[:risk] == HIGH
      end

      # Estate-wide format profile: what is held, in what quantity, and how much
      # of it is on a clock.
      #
      # @return [Hash]
      def profile
        counts = Asset.where(deleted_at: nil)
                      .group(Arel.sql("properties->>'content_type'"))
                      .count

        formats = counts.map do |content_type, count|
          classify(content_type).merge(content_type: content_type.presence || "unknown", count: count)
        end.sort_by { |f| [ risk_order(f[:risk]), -f[:count] ] }

        {
          formats: formats,
          totals: {
            assets: counts.values.sum,
            distinct_formats: counts.size,
            high_risk: formats.select { |f| f[:risk] == HIGH }.sum { |f| f[:count] },
            medium_risk: formats.select { |f| f[:risk] == MEDIUM }.sum { |f| f[:count] },
            low_risk: formats.select { |f| f[:risk] == LOW }.sum { |f| f[:count] },
          },
        }
      end

      private

      def risk_order(risk)
        [ HIGH, MEDIUM, LOW ].index(risk) || 99
      end
    end
  end
end
