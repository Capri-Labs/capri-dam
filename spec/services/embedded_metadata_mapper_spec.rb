require "rails_helper"

RSpec.describe EmbeddedMetadataMapper, type: :service do
  describe ".call" do
    let(:properties) do
      {
        "embedded_metadata" => {
          "XMP" => {
            "Title" => "Coconut Almond",
            "Creator" => "Jane Photographer",
            "Rights" => "© Deutsche Küche",
            "Subject" => %w[bread brioche],
          },
          "IPTC" => {
            "Headline" => "Giant Brioche Buns",
            "City" => "Berlin",
            "Country-PrimaryLocationName" => "Germany",
            "Credit" => "Specially Selected",
          },
          "EXIF" => {
            "Make" => "Canon",
            "Model" => "EOS R5",
            "FocalLength" => "50.0 mm",
            "FNumber" => 2.8,
            "ISO" => 100,
            "ExposureTime" => "1/200",
            "DateTimeOriginal" => "2024:01:01 10:00:00",
          },
        },
      }
    end

    subject(:mapped) { described_class.call(properties) }

    it "maps Dublin Core fields from XMP/IPTC/EXIF" do
      expect(mapped["dc:title"]).to eq("Coconut Almond")
      expect(mapped["dc:creator"]).to eq("Jane Photographer")
      expect(mapped["dc:rights"]).to eq("© Deutsche Küche")
      expect(mapped["dc:date"]).to eq("2024-01-01")
    end

    it "normalises EXIF datetime values on date fields to ISO YYYY-MM-DD" do
      dashed = described_class.call("embedded_metadata" => { "XMP" => { "CreateDate" => "2025-03-12T11:40:48+08:00" } })
      expect(dashed["dc:date"]).to eq("2025-03-12")
    end

    it "leaves date-like strings untouched for non-date metadata fields" do
      result = described_class.call("embedded_metadata" => { "XMP" => { "Creator" => "2025:03:12 11:40:48" } })
      expect(result["dc:creator"]).to eq("2025:03:12 11:40:48")
    end

    it "returns unparseable date strings unchanged" do
      result = described_class.call("embedded_metadata" => { "XMP" => { "CreateDate" => "Spring 2025" } })
      expect(result["dc:date"]).to eq("Spring 2025")
    end

    it "maps IPTC Photo Metadata Standard fields to the photoshop: namespace" do
      expect(mapped["photoshop:Headline"]).to eq("Giant Brioche Buns")
      expect(mapped["photoshop:City"]).to eq("Berlin")
      expect(mapped["photoshop:Country"]).to eq("Germany")
      expect(mapped["photoshop:Credit"]).to eq("Specially Selected")
      expect(mapped["dc:subject"]).to eq(%w[bread brioche])
    end

    it "maps EXIF camera fields, preferring FNumber and ISO" do
      expect(mapped["tiff:Make"]).to eq("Canon")
      expect(mapped["tiff:Model"]).to eq("EOS R5")
      expect(mapped["exif:FocalLength"]).to eq("50.0 mm")
      expect(mapped["exif:ApertureValue"]).to eq(2.8)
      expect(mapped["exif:ISOSpeedRatings"]).to eq(100)
      expect(mapped["exif:ShutterSpeedValue"]).to eq("1/200")
    end

    it "omits properties with no embedded source" do
      expect(mapped).not_to have_key("photoshop:Source")
    end

    it "falls back to later candidates when the first is blank" do
      properties["embedded_metadata"]["XMP"]["Creator"] = "  "
      properties["embedded_metadata"]["IPTC"]["By-line"] = "IPTC Author"
      expect(described_class.call(properties)["dc:creator"]).to eq("IPTC Author")
    end

    it "returns an empty hash when embedded_metadata is absent" do
      expect(described_class.call({})).to eq({})
      expect(described_class.call(nil)).to eq({})
      expect(described_class.call({ "embedded_metadata" => nil })).to eq({})
    end

    it "tolerates symbol keys" do
      symbolised = { embedded_metadata: { "EXIF" => { "Make" => "Nikon" } } }
      expect(described_class.call(symbolised)["tiff:Make"]).to eq("Nikon")
    end

    it "falls back to flat top-level properties when no grouped payload exists" do
      flat = {
        "camera_make" => "NIKON CORPORATION",
        "camera_model" => "NIKON D850",
        "date_taken" => "2024-05-01",
      }
      result = described_class.call(flat)
      expect(result["tiff:Make"]).to eq("NIKON CORPORATION")
      expect(result["tiff:Model"]).to eq("NIKON D850")
      expect(result["dc:date"]).to eq("2024-05-01")
    end

    it "prefers grouped embedded metadata over flat fallbacks" do
      combined = {
        "camera_make" => "NIKON CORPORATION",
        "embedded_metadata" => { "EXIF" => { "Make" => "Canon" } },
      }
      expect(described_class.call(combined)["tiff:Make"]).to eq("Canon")
    end

    context "with design/document assets lacking photographic tags" do
      it "derives dc:creator from authoring software as a low-confidence fallback" do
        props = { "embedded_metadata" => { "XMP" => { "CreatorTool" => "Adobe Photoshop CC 2017 (Macintosh)" } } }
        expect(described_class.call(props)["dc:creator"]).to eq("Adobe Photoshop CC 2017 (Macintosh)")
      end

      it "prefers a real creator over the software fallback" do
        props = {
          "embedded_metadata" => {
            "XMP" => { "Creator" => "Jane Doe", "CreatorTool" => "Adobe Photoshop" },
          },
        }
        expect(described_class.call(props)["dc:creator"]).to eq("Jane Doe")
      end

      it "does not derive dc:rights from an embedded ICC profile copyright (misleading — that's the color profile's own license, not the asset's rights)" do
        props = { "embedded_metadata" => { "ICC_Profile" => { "ProfileCopyright" => "Copyright 2007-2009 Adobe" } } }
        expect(described_class.call(props)["dc:rights"]).to be_nil
      end

      it "maps PDF document metadata onto Dublin Core fields" do
        props = {
          "embedded_metadata" => {
            "PDF" => { "Title" => "Annual Report", "Author" => "Finance Team", "Subject" => "FY2025" },
          },
        }
        result = described_class.call(props)
        expect(result["dc:title"]).to eq("Annual Report")
        expect(result["dc:creator"]).to eq("Finance Team")
        expect(result["dc:description"]).to eq("FY2025")
      end

      it "falls back to XMP:ModifyDate for dc:date when no create date exists" do
        props = { "embedded_metadata" => { "XMP" => { "ModifyDate" => "2025:03:27 18:24:11+08:00" } } }
        expect(described_class.call(props)["dc:date"]).to eq("2025-03-27")
      end

      it "derives dc:title from the Photoshop slice name as a last-resort fallback" do
        props = {
          "embedded_metadata" => {
            "Photoshop" => { "SlicesGroupName" => "846085_S_SpeciallySelected_GiantBriocheBuns_NP_S" },
          },
        }
        result = described_class.call(props)
        expect(result["dc:title"]).to eq("846085_S_SpeciallySelected_GiantBriocheBuns_NP_S")
        expect(result["photoshop:Headline"]).to eq("846085_S_SpeciallySelected_GiantBriocheBuns_NP_S")
      end

      it "prefers a real title over the Photoshop slice-name fallback" do
        props = {
          "embedded_metadata" => {
            "XMP" => { "Title" => "Giant Brioche Buns" },
            "Photoshop" => { "SlicesGroupName" => "846085_S_NP_S" },
          },
        }
        expect(described_class.call(props)["dc:title"]).to eq("Giant Brioche Buns")
      end
    end

    context "with XMP Basic / Media Management fields" do
      it "maps xmp: and xmpMM: properties for the XMP tab" do
        props = {
          "embedded_metadata" => {
            "XMP" => {
              "CreatorTool" => "Adobe Photoshop CC 2017 (Macintosh)",
              "CreateDate" => "2025:03:12 11:40:48+08:00",
              "ModifyDate" => "2025:03:27 18:24:11+08:00",
              "MetadataDate" => "2025:03:27 18:24:11+08:00",
              "Label" => "Approved",
              "Rating" => 5,
              "DocumentID" => "adobe:docid:photoshop:e9825f6e",
              "InstanceID" => "xmp.iid:e48764ce",
              "OriginalDocumentID" => "309AE9520993CC7501F0988836281225",
            },
          },
        }
        result = described_class.call(props)
        expect(result["xmp:CreatorTool"]).to eq("Adobe Photoshop CC 2017 (Macintosh)")
        expect(result["xmp:CreateDate"]).to eq("2025-03-12")
        expect(result["xmp:ModifyDate"]).to eq("2025-03-27")
        expect(result["xmp:MetadataDate"]).to eq("2025-03-27")
        expect(result["xmp:Label"]).to eq("Approved")
        expect(result["xmp:Rating"]).to eq(5)
        expect(result["xmpMM:DocumentID"]).to eq("adobe:docid:photoshop:e9825f6e")
        expect(result["xmpMM:InstanceID"]).to eq("xmp.iid:e48764ce")
        expect(result["xmpMM:OriginalDocumentID"]).to eq("309AE9520993CC7501F0988836281225")
      end
    end

    context "with Photoshop technical/production fields" do
      it "maps photoshop: properties for the Photoshop tab" do
        props = {
          "embedded_metadata" => {
            "Photoshop" => {
              "ColorMode" => "CMYK",
              "BitDepth" => 8,
              "LayerCount" => 2,
              "LayerNames" => %w[shadow Product],
              "Urgency" => "5",
              "Category" => "N",
              "SupplementalCategories" => %w[Retail],
              "Instructions" => "Do not crop",
              "TransmissionReference" => "REF-123",
            },
          },
        }
        result = described_class.call(props)
        expect(result["photoshop:ColorMode"]).to eq("CMYK")
        expect(result["photoshop:BitDepth"]).to eq(8)
        expect(result["photoshop:LayerCount"]).to eq(2)
        expect(result["photoshop:LayerNames"]).to eq(%w[shadow Product])
        expect(result["photoshop:Urgency"]).to eq("5")
        expect(result["photoshop:Category"]).to eq("N")
        expect(result["photoshop:SupplementalCategories"]).to eq(%w[Retail])
        expect(result["photoshop:Instructions"]).to eq("Do not crop")
        expect(result["photoshop:TransmissionReference"]).to eq("REF-123")
      end
    end

    context "with an embedded ICC color profile" do
      it "maps icc: properties for the ICC Profile tab" do
        props = {
          "embedded_metadata" => {
            "ICC_Profile" => {
              "ProfileDescription" => "Coated GRACoL 2006 (ISO 12647-2:2004)",
              "ColorSpaceData" => "CMYK",
              "ProfileClass" => "Output Device Profile",
              "DeviceManufacturer" => "Adobe Systems Inc.",
              "RenderingIntent" => "Media-Relative Colorimetric",
              "ProfileVersion" => "2.1.0",
            },
          },
        }
        result = described_class.call(props)
        expect(result["icc:ProfileDescription"]).to eq("Coated GRACoL 2006 (ISO 12647-2:2004)")
        expect(result["icc:ColorSpaceData"]).to eq("CMYK")
        expect(result["icc:ProfileClass"]).to eq("Output Device Profile")
        expect(result["icc:DeviceManufacturer"]).to eq("Adobe Systems Inc.")
        expect(result["icc:RenderingIntent"]).to eq("Media-Relative Colorimetric")
        expect(result["icc:ProfileVersion"]).to eq("2.1.0")
      end
    end
  end
end
