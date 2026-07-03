# frozen_string_literal: true

# Maps the raw, group-namespaced embedded metadata that
# {AssetProcessorWorker} extracts from an image (EXIF / IPTC / XMP / Photoshop /
# ICC) onto the +map_to_property+ keys used by the built-in metadata schemas.
#
# The metadata schema fields (see {MetadataSchemaSeeder}) reference standard
# namespaced property keys such as +dc:title+, +tiff:Make+ or
# +photoshop:Headline+ — these are the *real* XMP namespace prefixes defined by
# the Adobe XMP Specification and the IPTC Photo Metadata Standard, not
# invented ones. In particular:
#
#   * +dc:+       — Dublin Core (http://purl.org/dc/elements/1.1/)
#   * +tiff:+     — baseline TIFF/EXIF tags (Make, Model, Orientation, …) —
#                   per the Adobe XMP Spec Part 2 these live in the *TIFF*
#                   namespace, not +exif:+, even though they come from the
#                   EXIF IFD.
#   * +exif:+     — EXIF-specific tags (FocalLength, ISO, ExposureTime, …)
#   * +photoshop:+ — the IPTC Photo Metadata Standard's actual namespace for
#                   Headline / Credit / Source / City / Country / Urgency /
#                   Category / etc. (http://ns.adobe.com/photoshop/1.0/)
#   * +Iptc4xmpCore:+ — the *narrower* IPTC Core namespace, only used for a
#                   handful of controlled-vocabulary fields (e.g. Scene,
#                   IntellectualGenre) — most "IPTC" fields people expect are
#                   actually +photoshop:+ or +dc:+, per the spec above.
#   * +xmp:+ / +xmpMM:+ — XMP Basic / Media Management (CreatorTool, dates,
#                   DocumentID, InstanceID, …)
#   * +icc:+      — **not** a registered XMP namespace (ICC profile metadata
#                   lives in the profile's own binary header, not as XMP
#                   properties). Used here as a pragmatic, clearly-scoped
#                   in-house prefix purely to surface ICC profile header
#                   fields (description, color space, rendering intent, …) in
#                   the schema editor.
#
# The extractor, however, stores values grouped by the ExifTool group-0
# namespace (+"EXIF"+, +"XMP"+, +"IPTC"+, +"Photoshop"+, +"ICC_Profile"+, …).
# This service is the single source of truth that bridges the two so the
# +AssetMetadataPanel+ can pre-fill schema fields with the values already
# embedded in the file.
#
# Usage:
#   EmbeddedMetadataMapper.call(asset.properties)
#   # => { "dc:title" => "Coconut Almond", "tiff:Make" => "Canon", ... }
#
# The result only contains non-blank values, so callers can safely merge it as a
# set of defaults without clobbering fields that have no embedded source.
class EmbeddedMetadataMapper
  # Schema +map_to_property+ key => ordered list of ExifTool +Group:Tag+
  # candidates.  The first candidate that resolves to a non-blank value wins.
  # Candidate ordering within each list runs from most-authoritative to
  # least-authoritative.  The last one or two entries in several lists are
  # deliberately *low-confidence* fallbacks (e.g. deriving +dc:creator+ from the
  # authoring +Software+).  They exist so design/document assets (PSD, AI,
  # PDF, PNG, …) that carry no photographic descriptive tags still pre-fill
  # *something* rather than showing every field blank.  See
  # +LOW_CONFIDENCE_NOTE+ below; a future refactor may gate these behind a
  # confidence flag.
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
      XMP:UsageTerms XMP:WebStatement
    ],
    "dc:subject" => %w[XMP:Subject IPTC:Keywords XMP:Keywords XMP:HierarchicalSubject],

    # ── IPTC Photo Metadata Standard (IPTC tab) ──────────────────────────
    # Per the IPTC Photo Metadata Standard, these are stored in the
    # `photoshop:` XMP namespace, not `Iptc4xmpCore:` (a common misconception —
    # Iptc4xmpCore is reserved for a narrower set of controlled-vocabulary
    # fields such as Scene/IntellectualGenre, not Headline/Credit/City/etc.).
    "photoshop:Headline" => %w[XMP:Headline IPTC:Headline Photoshop:Headline XMP:Title IPTC:ObjectName Photoshop:SlicesGroupName],
    "photoshop:Credit" => %w[IPTC:Credit XMP:Credit Photoshop:Credit XMP:Source IPTC:Source],
    "photoshop:Source" => %w[IPTC:Source XMP:Source Photoshop:Source XMP:Credit],
    "photoshop:City" => %w[IPTC:City XMP:City Photoshop:City XMP:LocationCreatedCity XMP:LocationShownCity],
    "photoshop:Country" => %w[
      IPTC:Country-PrimaryLocationName XMP:Country XMP:CountryName Photoshop:Country
      XMP:LocationCreatedCountryName XMP:LocationShownCountryName
    ],

    # ── TIFF baseline tags (Camera tab) ──────────────────────────────────
    # Make/Model are baseline TIFF tags per the Adobe XMP EXIF spec, not `exif:`.
    "tiff:Make" => %w[EXIF:Make XMP:Make TIFF:Make camera_make],
    "tiff:Model" => %w[EXIF:Model XMP:Model TIFF:Model camera_model],

    # ── EXIF-specific tags (Camera tab) ──────────────────────────────────
    "exif:FocalLength" => %w[EXIF:FocalLength Composite:FocalLength35efl EXIF:FocalLengthIn35mmFormat XMP:FocalLength],
    "exif:ApertureValue" => %w[EXIF:FNumber EXIF:ApertureValue Composite:Aperture XMP:FNumber XMP:ApertureValue],
    "exif:ISOSpeedRatings" => %w[EXIF:ISO EXIF:ISOSpeedRatings Composite:ISO XMP:ISO XMP:ISOSpeedRatings],
    "exif:ShutterSpeedValue" => %w[
      EXIF:ExposureTime EXIF:ShutterSpeedValue Composite:ShutterSpeed
      XMP:ShutterSpeedValue XMP:ExposureTime
    ],

    # ── XMP Basic / Media Management (XMP tab) ───────────────────────────
    "xmp:CreatorTool" => %w[XMP:CreatorTool],
    "xmp:CreateDate" => %w[XMP:CreateDate],
    "xmp:ModifyDate" => %w[XMP:ModifyDate],
    "xmp:MetadataDate" => %w[XMP:MetadataDate],
    "xmp:Label" => %w[XMP:Label],
    "xmp:Rating" => %w[XMP:Rating],
    "xmpMM:DocumentID" => %w[XMP:DocumentID],
    "xmpMM:InstanceID" => %w[XMP:InstanceID],
    "xmpMM:OriginalDocumentID" => %w[XMP:OriginalDocumentID],

    # ── Photoshop technical/production tags (Photoshop tab) ──────────────
    "photoshop:ColorMode" => %w[Photoshop:ColorMode XMP:ColorMode],
    "photoshop:BitDepth" => %w[Photoshop:BitDepth],
    "photoshop:LayerCount" => %w[Photoshop:LayerCount],
    "photoshop:LayerNames" => %w[Photoshop:LayerNames Photoshop:LayerUnicodeNames],
    "photoshop:Urgency" => %w[Photoshop:Urgency IPTC:Urgency],
    "photoshop:Category" => %w[Photoshop:Category IPTC:Category],
    "photoshop:SupplementalCategories" => %w[Photoshop:SupplementalCategories IPTC:SupplementalCategories],
    "photoshop:Instructions" => %w[Photoshop:Instructions IPTC:SpecialInstructions],
    "photoshop:TransmissionReference" => %w[Photoshop:TransmissionReference IPTC:TransmissionReference],

    # ── ICC color profile header (ICC_Profile tab; in-house `icc:` prefix — see note above) ──
    "icc:ProfileDescription" => %w[ICC_Profile:ProfileDescription],
    "icc:ColorSpaceData" => %w[ICC_Profile:ColorSpaceData],
    "icc:ProfileClass" => %w[ICC_Profile:ProfileClass],
    "icc:DeviceManufacturer" => %w[ICC_Profile:DeviceManufacturer],
    "icc:RenderingIntent" => %w[ICC_Profile:RenderingIntent],
    "icc:ProfileVersion" => %w[ICC_Profile:ProfileVersion],
  }.freeze

  # Reference note for maintainers: the trailing candidates in +dc:creator+
  # (+XMP:CreatorTool+, +EXIF:Software+) and +dc:title+ / +photoshop:Headline+
  # (+Photoshop:SlicesGroupName+ — the export/web-slice name) are heuristic
  # fallbacks, not true descriptive values.  Keep them last so genuine
  # descriptive tags always win.
  #
  # +dc:rights+ deliberately does **not** fall back to +ICC_Profile:ProfileCopyright+:
  # that field is the copyright notice of the embedded *color profile* (e.g.
  # "Copyright Adobe Systems Incorporated"), not the asset's usage rights — using
  # it as a fallback previously caused assets to be mis-labelled with Adobe's ICC
  # profile license text as their rights holder. Better to leave +dc:rights+ blank
  # than show a misleading value.
  LOW_CONFIDENCE_NOTE = "creator←Software, title←Photoshop slice name are heuristic fallbacks"

  # +map_to_property+ keys backed by a schema +date+ field.  Embedded dates are
  # stored by ExifTool in the EXIF "YYYY:MM:DD HH:MM:SS" form, which an HTML
  # +<input type="date">+ cannot render.  Values for these keys are normalised to
  # ISO +YYYY-MM-DD+ so the schema editor pre-fills them correctly.
  DATE_PROPERTIES = %w[dc:date xmp:CreateDate xmp:ModifyDate xmp:MetadataDate].freeze

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
