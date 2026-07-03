import { mapEmbeddedMetadata } from '../../../app/javascript/utils/embeddedMetadataMapper';

describe('mapEmbeddedMetadata', () => {
  const properties = {
    embedded_metadata: {
      XMP: {
        Title: 'Coconut Almond',
        Creator: 'Jane Photographer',
        Rights: '© Deutsche Küche',
        Subject: ['bread', 'brioche'],
      },
      IPTC: {
        Headline: 'Giant Brioche Buns',
        City: 'Berlin',
        'Country-PrimaryLocationName': 'Germany',
        Credit: 'Specially Selected',
      },
      EXIF: {
        Make: 'Canon',
        Model: 'EOS R5',
        FocalLength: '50.0 mm',
        FNumber: 2.8,
        ISO: 100,
        ExposureTime: '1/200',
        DateTimeOriginal: '2024:01:01 10:00:00',
      },
    },
  };

  it('maps Dublin Core, IPTC and EXIF fields to schema property keys', () => {
    const mapped = mapEmbeddedMetadata(properties);
    expect(mapped['dc:title']).toBe('Coconut Almond');
    expect(mapped['dc:creator']).toBe('Jane Photographer');
    expect(mapped['dc:rights']).toBe('© Deutsche Küche');
    expect(mapped['dc:date']).toBe('2024-01-01');
    expect(mapped['Iptc4xmpCore:Headline']).toBe('Giant Brioche Buns');
    expect(mapped['Iptc4xmpCore:CountryName']).toBe('Germany');
    expect(mapped['Iptc4xmpCore:SubjectCode']).toEqual(['bread', 'brioche']);
    expect(mapped['exif:Make']).toBe('Canon');
    expect(mapped['exif:ApertureValue']).toBe(2.8);
    expect(mapped['exif:ISOSpeedRatings']).toBe(100);
    expect(mapped['exif:ShutterSpeedValue']).toBe('1/200');
  });

  it('omits properties without an embedded source', () => {
    const mapped = mapEmbeddedMetadata(properties);
    expect(mapped['Iptc4xmpCore:Source']).toBeUndefined();
  });

  it('falls back to later candidates when earlier ones are blank', () => {
    const props = {
      embedded_metadata: {
        XMP: { Creator: '   ' },
        IPTC: { 'By-line': 'IPTC Author' },
      },
    };
    expect(mapEmbeddedMetadata(props)['dc:creator']).toBe('IPTC Author');
  });

  it('normalises EXIF datetime dates to ISO YYYY-MM-DD on date fields', () => {
    expect(mapEmbeddedMetadata({ embedded_metadata: { EXIF: { DateTimeOriginal: '2024:01:01 10:00:00' } } })['dc:date']).toBe('2024-01-01');
    expect(mapEmbeddedMetadata({ embedded_metadata: { XMP: { CreateDate: '2025-03-12T11:40:48+08:00' } } })['dc:date']).toBe('2025-03-12');
  });

  it('returns an empty object when embedded_metadata is missing', () => {
    expect(mapEmbeddedMetadata({})).toEqual({});
    expect(mapEmbeddedMetadata(null)).toEqual({});
    expect(mapEmbeddedMetadata({ embedded_metadata: null })).toEqual({});
  });

  it('falls back to flat top-level properties when no grouped payload exists', () => {
    const props = {
      camera_make: 'NIKON CORPORATION',
      camera_model: 'NIKON D850',
      date_taken: '2024-05-01',
    };
    const mapped = mapEmbeddedMetadata(props);
    expect(mapped['exif:Make']).toBe('NIKON CORPORATION');
    expect(mapped['exif:Model']).toBe('NIKON D850');
    expect(mapped['dc:date']).toBe('2024-05-01');
  });

  it('prefers grouped embedded metadata over flat fallbacks', () => {
    const props = {
      camera_make: 'NIKON CORPORATION',
      embedded_metadata: { EXIF: { Make: 'Canon' } },
    };
    expect(mapEmbeddedMetadata(props)['exif:Make']).toBe('Canon');
  });

  describe('design/document fallbacks', () => {
    it('derives dc:creator from authoring software when no creator exists', () => {
      const props = { embedded_metadata: { XMP: { CreatorTool: 'Adobe Photoshop CC 2017 (Macintosh)' } } };
      expect(mapEmbeddedMetadata(props)['dc:creator']).toBe('Adobe Photoshop CC 2017 (Macintosh)');
    });

    it('prefers a real creator over the software fallback', () => {
      const props = { embedded_metadata: { XMP: { Creator: 'Jane Doe', CreatorTool: 'Adobe Photoshop' } } };
      expect(mapEmbeddedMetadata(props)['dc:creator']).toBe('Jane Doe');
    });

    it('derives dc:rights from an embedded ICC profile copyright', () => {
      const props = { embedded_metadata: { ICC_Profile: { ProfileCopyright: 'Copyright 2007-2009 Adobe' } } };
      expect(mapEmbeddedMetadata(props)['dc:rights']).toBe('Copyright 2007-2009 Adobe');
    });

    it('maps PDF document metadata onto Dublin Core fields', () => {
      const props = { embedded_metadata: { PDF: { Title: 'Annual Report', Author: 'Finance Team', Subject: 'FY2025' } } };
      const mapped = mapEmbeddedMetadata(props);
      expect(mapped['dc:title']).toBe('Annual Report');
      expect(mapped['dc:creator']).toBe('Finance Team');
      expect(mapped['dc:description']).toBe('FY2025');
    });

    it('falls back to XMP:ModifyDate for dc:date when no create date exists', () => {
      const props = { embedded_metadata: { XMP: { ModifyDate: '2025:03:27 18:24:11+08:00' } } };
      expect(mapEmbeddedMetadata(props)['dc:date']).toBe('2025-03-27');
    });
  });
});
