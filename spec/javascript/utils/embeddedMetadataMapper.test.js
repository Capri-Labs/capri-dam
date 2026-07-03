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
    expect(mapped['dc:subject']).toEqual(['bread', 'brioche']);
    // IPTC Photo Metadata Standard fields live in the `photoshop:` XMP
    // namespace, not `Iptc4xmpCore:` (see embeddedMetadataMapper.js header).
    expect(mapped['photoshop:Headline']).toBe('Giant Brioche Buns');
    expect(mapped['photoshop:Country']).toBe('Germany');
    // Make/Model are baseline TIFF tags per the Adobe XMP EXIF spec.
    expect(mapped['tiff:Make']).toBe('Canon');
    expect(mapped['exif:ApertureValue']).toBe(2.8);
    expect(mapped['exif:ISOSpeedRatings']).toBe(100);
    expect(mapped['exif:ShutterSpeedValue']).toBe('1/200');
  });

  it('omits properties without an embedded source', () => {
    const mapped = mapEmbeddedMetadata(properties);
    expect(mapped['photoshop:Source']).toBeUndefined();
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
    expect(mapped['tiff:Make']).toBe('NIKON CORPORATION');
    expect(mapped['tiff:Model']).toBe('NIKON D850');
    expect(mapped['dc:date']).toBe('2024-05-01');
  });

  it('prefers grouped embedded metadata over flat fallbacks', () => {
    const props = {
      camera_make: 'NIKON CORPORATION',
      embedded_metadata: { EXIF: { Make: 'Canon' } },
    };
    expect(mapEmbeddedMetadata(props)['tiff:Make']).toBe('Canon');
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

    it('does not derive dc:rights from an embedded ICC profile copyright (misleading — that is the color profile license, not the asset rights)', () => {
      const props = { embedded_metadata: { ICC_Profile: { ProfileCopyright: 'Copyright 2007-2009 Adobe' } } };
      expect(mapEmbeddedMetadata(props)['dc:rights']).toBeUndefined();
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

  describe('XMP Basic / Media Management fields', () => {
    it('maps xmp: and xmpMM: properties for the XMP tab', () => {
      const props = {
        embedded_metadata: {
          XMP: {
            CreatorTool: 'Adobe Photoshop CC 2017 (Macintosh)',
            CreateDate: '2025:03:12 11:40:48+08:00',
            ModifyDate: '2025:03:27 18:24:11+08:00',
            MetadataDate: '2025:03:27 18:24:11+08:00',
            Label: 'Approved',
            Rating: 5,
            DocumentID: 'adobe:docid:photoshop:e9825f6e',
            InstanceID: 'xmp.iid:e48764ce',
            OriginalDocumentID: '309AE9520993CC7501F0988836281225',
          },
        },
      };
      const mapped = mapEmbeddedMetadata(props);
      expect(mapped['xmp:CreatorTool']).toBe('Adobe Photoshop CC 2017 (Macintosh)');
      expect(mapped['xmp:CreateDate']).toBe('2025-03-12');
      expect(mapped['xmp:ModifyDate']).toBe('2025-03-27');
      expect(mapped['xmp:MetadataDate']).toBe('2025-03-27');
      expect(mapped['xmp:Label']).toBe('Approved');
      expect(mapped['xmp:Rating']).toBe(5);
      expect(mapped['xmpMM:DocumentID']).toBe('adobe:docid:photoshop:e9825f6e');
      expect(mapped['xmpMM:InstanceID']).toBe('xmp.iid:e48764ce');
      expect(mapped['xmpMM:OriginalDocumentID']).toBe('309AE9520993CC7501F0988836281225');
    });
  });

  describe('Photoshop technical/production fields', () => {
    it('maps photoshop: properties for the Photoshop tab', () => {
      const props = {
        embedded_metadata: {
          Photoshop: {
            ColorMode: 'CMYK',
            BitDepth: 8,
            LayerCount: 2,
            LayerNames: ['shadow', 'Product'],
            Urgency: '5',
            Category: 'N',
            SupplementalCategories: ['Retail'],
            Instructions: 'Do not crop',
            TransmissionReference: 'REF-123',
          },
        },
      };
      const mapped = mapEmbeddedMetadata(props);
      expect(mapped['photoshop:ColorMode']).toBe('CMYK');
      expect(mapped['photoshop:BitDepth']).toBe(8);
      expect(mapped['photoshop:LayerCount']).toBe(2);
      expect(mapped['photoshop:LayerNames']).toEqual(['shadow', 'Product']);
      expect(mapped['photoshop:Urgency']).toBe('5');
      expect(mapped['photoshop:Category']).toBe('N');
      expect(mapped['photoshop:SupplementalCategories']).toEqual(['Retail']);
      expect(mapped['photoshop:Instructions']).toBe('Do not crop');
      expect(mapped['photoshop:TransmissionReference']).toBe('REF-123');
    });
  });

  describe('ICC color profile fields', () => {
    it('maps icc: properties for the ICC Profile tab', () => {
      const props = {
        embedded_metadata: {
          ICC_Profile: {
            ProfileDescription: 'Coated GRACoL 2006 (ISO 12647-2:2004)',
            ColorSpaceData: 'CMYK',
            ProfileClass: 'Output Device Profile',
            DeviceManufacturer: 'Adobe Systems Inc.',
            RenderingIntent: 'Media-Relative Colorimetric',
            ProfileVersion: '2.1.0',
          },
        },
      };
      const mapped = mapEmbeddedMetadata(props);
      expect(mapped['icc:ProfileDescription']).toBe('Coated GRACoL 2006 (ISO 12647-2:2004)');
      expect(mapped['icc:ColorSpaceData']).toBe('CMYK');
      expect(mapped['icc:ProfileClass']).toBe('Output Device Profile');
      expect(mapped['icc:DeviceManufacturer']).toBe('Adobe Systems Inc.');
      expect(mapped['icc:RenderingIntent']).toBe('Media-Relative Colorimetric');
      expect(mapped['icc:ProfileVersion']).toBe('2.1.0');
    });
  });
});

