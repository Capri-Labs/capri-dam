// Maps the group-namespaced embedded metadata extracted from an image
// (EXIF / IPTC / XMP) onto the `map_to_property` keys used by the metadata
// schemas, so the AssetMetadataPanel can pre-fill schema fields with the values
// embedded in the file.
//
// This mirrors the backend `EmbeddedMetadataMapper` service. Only non-blank
// values are returned, so callers can merge the result as defaults without
// clobbering fields that have no embedded source.

// Candidate ordering within each list runs from most-authoritative to
// least-authoritative. The last one or two entries in several lists are
// deliberately low-confidence fallbacks (e.g. deriving `dc:creator` from the
// authoring `Software`, or `dc:rights` from an embedded ICC profile's
// copyright). They let design/document assets (PSD, AI, PDF, PNG, …) that carry
// no photographic descriptive tags still pre-fill something rather than showing
// every field blank. Keep the heuristic entries last so genuine descriptive
// tags always win. Mirrors the backend `EmbeddedMetadataMapper::PROPERTY_SOURCES`.
const PROPERTY_SOURCES = {
  'dc:title': [
    'XMP:Title', 'IPTC:ObjectName', 'XMP:Headline', 'IPTC:Headline',
    'PDF:Title', 'PNG:Title', 'XMP:Label', 'Photoshop:SlicesGroupName',
  ],
  'dc:description': [
    'XMP:Description', 'IPTC:Caption-Abstract', 'EXIF:ImageDescription',
    'PDF:Subject', 'PNG:Description', 'XMP:UserComment', 'EXIF:UserComment',
  ],
  'dc:creator': [
    'XMP:Creator', 'IPTC:By-line', 'EXIF:Artist', 'PDF:Author', 'PNG:Author',
    'XMP:Author', 'XMP:Owner', 'EXIF:OwnerName', 'XMP:CreatorTool', 'EXIF:Software',
  ],
  'dc:date': [
    'EXIF:DateTimeOriginal', 'XMP:CreateDate', 'EXIF:CreateDate', 'XMP:DateCreated',
    'IPTC:DateCreated', 'PDF:CreateDate', 'PNG:CreationTime', 'XMP:MetadataDate',
    'EXIF:ModifyDate', 'XMP:ModifyDate', 'date_taken',
  ],
  'dc:rights': [
    'XMP:Rights', 'IPTC:CopyrightNotice', 'EXIF:Copyright',
    'XMP:UsageTerms', 'XMP:WebStatement', 'ICC_Profile:ProfileCopyright',
  ],

  'Iptc4xmpCore:Headline': ['XMP:Headline', 'IPTC:Headline', 'XMP:Title', 'IPTC:ObjectName', 'Photoshop:SlicesGroupName'],
  'Iptc4xmpCore:Byline': ['IPTC:By-line', 'XMP:Creator', 'EXIF:Artist', 'PDF:Author', 'XMP:Author'],
  'Iptc4xmpCore:CreditLine': ['IPTC:Credit', 'XMP:Credit', 'XMP:Source', 'IPTC:Source'],
  'Iptc4xmpCore:Source': ['IPTC:Source', 'XMP:Source', 'XMP:Credit'],
  'Iptc4xmpCore:Description': ['XMP:Description', 'IPTC:Caption-Abstract', 'EXIF:ImageDescription', 'PDF:Subject'],
  'Iptc4xmpCore:City': ['IPTC:City', 'XMP:City', 'XMP:LocationCreatedCity', 'XMP:LocationShownCity'],
  'Iptc4xmpCore:CountryName': [
    'IPTC:Country-PrimaryLocationName', 'XMP:Country', 'XMP:CountryName',
    'XMP:LocationCreatedCountryName', 'XMP:LocationShownCountryName',
  ],
  'Iptc4xmpCore:SubjectCode': ['XMP:Subject', 'IPTC:Keywords', 'XMP:Keywords', 'XMP:SubjectCode', 'XMP:HierarchicalSubject'],

  'exif:Make': ['EXIF:Make', 'XMP:Make', 'camera_make'],
  'exif:Model': ['EXIF:Model', 'XMP:Model', 'camera_model'],
  'exif:FocalLength': ['EXIF:FocalLength', 'Composite:FocalLength35efl', 'EXIF:FocalLengthIn35mmFormat', 'XMP:FocalLength'],
  'exif:ApertureValue': ['EXIF:FNumber', 'EXIF:ApertureValue', 'Composite:Aperture', 'XMP:FNumber', 'XMP:ApertureValue'],
  'exif:ISOSpeedRatings': ['EXIF:ISO', 'EXIF:ISOSpeedRatings', 'Composite:ISO', 'XMP:ISO', 'XMP:ISOSpeedRatings'],
  'exif:ShutterSpeedValue': [
    'EXIF:ExposureTime', 'EXIF:ShutterSpeedValue', 'Composite:ShutterSpeed',
    'XMP:ShutterSpeedValue', 'XMP:ExposureTime',
  ],
};

// Schema `date` fields store their value as an ISO YYYY-MM-DD string. Embedded
// dates come from ExifTool in the "YYYY:MM:DD HH:MM:SS" form, which an HTML
// <input type="date"> cannot render, so values for these keys are normalised.
const DATE_PROPERTIES = new Set(['dc:date']);

// Converts an EXIF-style datetime ("YYYY:MM:DD HH:MM:SS±TZ") to ISO YYYY-MM-DD.
// Values already ISO (or unrecognised) are returned unchanged.
function normaliseDate(value) {
  if (typeof value !== 'string') return value;
  const m = value.match(/^(\d{4})[:-](\d{2})[:-](\d{2})/);
  return m ? `${m[1]}-${m[2]}-${m[3]}` : value;
}

function isBlank(value) {
  if (value === null || value === undefined) return true;
  if (typeof value === 'string') return value.trim() === '';
  if (Array.isArray(value)) return value.length === 0;
  if (typeof value === 'object') return Object.keys(value).length === 0;
  return false;
}

// Resolves an ordered list of candidates. A "Group:Tag" candidate looks up the
// grouped embedded metadata; a bare "key" candidate (no colon) looks up the flat
// top-level `properties` hash, so assets processed via the MiniMagick path (which
// stores `camera_make`, `camera_model`, `date_taken`, … at the top level) still
// pre-fill schema fields even without a grouped ExifTool payload.
function resolve(grouped, properties, candidates) {
  for (const candidate of candidates) {
    const idx = candidate.indexOf(':');
    if (idx === -1) {
      const value = properties ? properties[candidate] : undefined;
      if (!isBlank(value)) return value;
      continue;
    }
    const group = candidate.slice(0, idx);
    const tag = candidate.slice(idx + 1);
    const bucket = grouped[group];
    if (!bucket || typeof bucket !== 'object') continue;
    const value = bucket[tag];
    if (!isBlank(value)) return value;
  }
  return undefined;
}

// Given an asset's `properties` object, return a `{ map_to_property: value }`
// map derived from its embedded metadata.
export function mapEmbeddedMetadata(properties) {
  if (!properties || typeof properties !== 'object') return {};
  const grouped = (properties.embedded_metadata && typeof properties.embedded_metadata === 'object')
    ? properties.embedded_metadata
    : {};

  const mapped = {};
  for (const [property, candidates] of Object.entries(PROPERTY_SOURCES)) {
    let value = resolve(grouped, properties, candidates);
    if (DATE_PROPERTIES.has(property)) value = normaliseDate(value);
    if (!isBlank(value)) mapped[property] = value;
  }
  return mapped;
}

export default mapEmbeddedMetadata;
