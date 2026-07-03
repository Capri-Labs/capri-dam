# frozen_string_literal: true

# Maps the raw, group-namespaced embedded metadata that
# {AssetProcessorWorker} extracts from an image (EXIF / IPTC / XMP / Photoshop /
# ICC) onto the +map_to_property+ keys used by the built-in metadata schemas.
#
# The metadata schema fields (see +db/migrate/*create_metadata_schemas.rb+)
# reference standard namespaced property keys such as +dc:title+, +exif:Make+ or
# +Iptc4xmpCore:Headline+.  The extractor, however, stores values grouped by the
# ExifTool group-0 namespace (+"EXIF"+, +"XMP"+, +"IPTC"+, …).  This service is
# the single source of truth that bridges the two so the +AssetMetadataPanel+
# can pre-fill schema fields with the values already embedded in the file.
#
# Usage:
#   EmbeddedMetadataMapper.call(asset.properties)
#   # => { "dc:title" => "Coconut Almond", "exif:Make" => "Canon", ... }
#
# The result only contains non-blank values, so callers can safely merge it as a
# set of defaults without clobbering fields that have no embedded source.
class EmbeddedMetadataMapper
  # Schema +map_to_property+ key => ordered list of ExifTool +Group:Tag+
  # candidates.  The first candidate that resolves to a non-blank value wins.
  # Candidate ordering within each list runs from most-authoritative to
  # least-authoritative.  The last one or two entries in several lists are
  # deliberately *low-confidence* fallbacks (e.g. deriving +dc:creator+ from the
  # authoring +Software+, or +dc:rights+ from an embedded ICC profile's
  # copyright).  They exist so design/document assets (PSD, AI, PDF, PNG, …) that
  # carry no photographic descriptive tags still pre-fill *something* rather than
  # showing every field blank.  See +LOW_CONFIDENCE_NOTE+ below; a future refactor
  # may gate these behind a confidence flag.
  PROPERTY_SOURCES = {
    # ── Dublin Core (Basic tab) ──────────────────────────────────────────
    "dc:title" => %w[
      XMP:Title IPTC:ObjectName XMP:Headline IPTC:Headline
      PDF:Title PNG:Title XMP:Label Photoshop:SlicesGroupName
    ],
    "dc:description" => %w[
      XMP:Description IPTC:Caption-Abstract EXIF:ImageDescription
      PDF:Subject PNG:Description XMP:UserComment EXIF:UserComment
    ],
    "dc:creator" => %w[
      XMP:Creator IPTC:By-line EXIF:Artist PDF:Author PNG:Author
      XMP:Author XMP:Owner EXIF:OwnerName XMP:CreatorTool EXIF:Software
    ],
    "dc:date" => %w[
      EXIF:DateTimeOriginal XMP:CreateDate EXIF:CreateDate XMP:DateCreated
      IPTC:DateCreated PDF:CreateDate PNG:CreationTime XMP:MetadataDate
      EXIF:ModifyDate XMP:ModifyDate date_taken
    ],
    "dc:rights" => %w[
      XMP:Rights IPTC:CopyrightNotice EXIF:Copyright
      XMP:UsageTerms XMP:WebStatement ICC_Profile:ProfileCopyright
    ],

    # ── IPTC Core (IPTC tab) ─────────────────────────────────────────────
    "Iptc4xmpCore:Headline" => %w[XMP:Headline IPTC:Headline XMP:Title IPTC:ObjectName Photoshop:SlicesGroupName],
    "Iptc4xmpCore:Byline" => %w[IPTC:By-line XMP:Creator EXIF:Artist PDF:Author XMP:Author],
    "Iptc4xmpCore:CreditLine" => %w[IPTC:Credit XMP:Credit XMP:Source IPTC:Source],
    "Iptc4xmpCore:Source" => %w[IPTC:Source XMP:Source XMP:Credit],
    "Iptc4xmpCore:Description" => %w[XMP:Description IPTC:Caption-Abstract EXIF:ImageDescription PDF:Subject],
    "Iptc4xmpCore:City" => %w[IPTC:City XMP:City XMP:LocationCreatedCity XMP:LocationShownCity],
    "Iptc4xmpCore:CountryName" => %w[
      IPTC:Country-PrimaryLocationName XMP:Country XMP:CountryName
      XMP:LocationCreatedCountryName XMP:LocationShownCountryName
    ],
    "Iptc4xmpCore:SubjectCode" => %w[XMP:Subject IPTC:Keywords XMP:Keywords XMP:SubjectCode XMP:HierarchicalSubject],

    # ── EXIF (Camera tab) ────────────────────────────────────────────────
    "exif:Make" => %w[EXIF:Make XMP:Make camera_make],
    "exif:Model" => %w[EXIF:Model XMP:Model camera_model],
    "exif:FocalLength" => %w[EXIF:FocalLength Composite:FocalLength35efl EXIF:FocalLengthIn35mmFormat XMP:FocalLength],
    "exif:ApertureValue" => %w[EXIF:FNumber EXIF:ApertureValue Composite:Aperture XMP:FNumber XMP:ApertureValue],
    "exif:ISOSpeedRatings" => %w[EXIF:ISO EXIF:ISOSpeedRatings Composite:ISO XMP:ISO XMP:ISOSpeedRatings],
    "exif:ShutterSpeedValue" => %w[
      EXIF:ExposureTime EXIF:ShutterSpeedValue Composite:ShutterSpeed
      XMP:ShutterSpeedValue XMP:ExposureTime
    ],
  }.freeze

  # Reference note for maintainers: the trailing candidates in +dc:creator+
  # (+XMP:CreatorTool+, +EXIF:Software+), +dc:rights+
  # (+ICC_Profile:ProfileCopyright+) and +dc:title+ / +Iptc4xmpCore:Headline+
  # (+Photoshop:SlicesGroupName+ — the export/web-slice name) are heuristic
  # fallbacks, not true descriptive values.  Keep them last so genuine
  # descriptive tags always win.
  LOW_CONFIDENCE_NOTE = "creator←Software, rights←ICC copyright, title←Photoshop slice name are heuristic fallbacks"

  # +map_to_property+ keys backed by a schema +date+ field.  Embedded dates are
  # stored by ExifTool in the EXIF "YYYY:MM:DD HH:MM:SS" form, which an HTML
  # +<input type="date">+ cannot render.  Values for these keys are normalised to
  # ISO +YYYY-MM-DD+ so the schema editor pre-fills them correctly.
  DATE_PROPERTIES = %w[dc:date].freeze

  # @param properties [Hash] an asset's +properties+ hash (must contain the
  #   grouped +"embedded_metadata"+ payload; string or symbol keys accepted)
  # @return [Hash{String=>Object}] resolved +map_to_property => value+ pairs
  def self.call(properties)
    new(properties).call
  end

  # @param properties [Hash]
  def initialize(properties)
    @properties = properties.is_a?(Hash) ? properties : {}
    @grouped = normalise_grouped(properties)
  end

  # @return [Hash{String=>Object}]
  def call
    return {} if @grouped.empty? && @properties.empty?

    PROPERTY_SOURCES.each_with_object({}) do |(property, candidates), acc|
      value = resolve(candidates)
      value = normalise_date(value) if DATE_PROPERTIES.include?(property)
      acc[property] = value unless blank_value?(value)
    end
  end

  private

  # Converts an EXIF-style datetime ("YYYY:MM:DD HH:MM:SS±TZ") to an ISO
  # +YYYY-MM-DD+ date so schema +date+ fields render it.  Values already in ISO
  # form (or unrecognised) are returned unchanged.
  #
  # @param value [Object]
  # @return [Object]
  def normalise_date(value)
    return value unless value.is_a?(String)

    if (m = value.match(/\A(\d{4})[:-](\d{2})[:-](\d{2})/))
      "#{m[1]}-#{m[2]}-#{m[3]}"
    else
      value
    end
  end

  # Extracts the grouped +embedded_metadata+ hash from an asset's properties,
  # tolerating both string and symbol keys.
  #
  # @param properties [Hash, nil]
  # @return [Hash]
  def normalise_grouped(properties)
    return {} unless properties.is_a?(Hash)

    grouped = properties["embedded_metadata"] || properties[:embedded_metadata]
    grouped.is_a?(Hash) ? grouped : {}
  end

  # @param candidates [Array<String>] ordered lookups.  A +"Group:Tag"+ candidate
  #   resolves against the grouped +embedded_metadata+; a bare +"key"+ candidate
  #   (no colon) resolves against the flat top-level +properties+ hash — this lets
  #   assets processed via the MiniMagick path (which stores +camera_make+,
  #   +camera_model+, +date_taken+ … at the top level) still pre-fill schema
  #   fields even when no grouped ExifTool payload is present.
  # @return [Object, nil] the first non-blank value
  def resolve(candidates)
    candidates.each do |candidate|
      group, tag = candidate.split(":", 2)

      value =
        if tag.nil?
          # Bare key → flat top-level property.
          @properties.fetch(group) { @properties.fetch(group.to_sym, nil) }
        else
          # Use fetch (never []) so a missing key does not trigger a default-proc
          # that would mutate a caller's auto-vivifying Hash.
          bucket = @grouped.fetch(group) { @grouped.fetch(group.to_sym, nil) }
          next unless bucket.is_a?(Hash)

          bucket.fetch(tag) { bucket.fetch(tag.to_sym, nil) }
        end

      return value unless blank_value?(value)
    end
    nil
  end

  # @return [Boolean] true for nil, empty string/array/hash values
  def blank_value?(value)
    return true if value.nil?
    return value.strip.empty? if value.is_a?(String)
    return value.empty? if value.respond_to?(:empty?)

    false
  end
end
