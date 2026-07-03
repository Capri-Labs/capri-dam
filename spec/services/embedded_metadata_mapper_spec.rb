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

    it "maps IPTC core fields" do
      expect(mapped["Iptc4xmpCore:Headline"]).to eq("Giant Brioche Buns")
      expect(mapped["Iptc4xmpCore:City"]).to eq("Berlin")
      expect(mapped["Iptc4xmpCore:CountryName"]).to eq("Germany")
      expect(mapped["Iptc4xmpCore:CreditLine"]).to eq("Specially Selected")
      expect(mapped["Iptc4xmpCore:SubjectCode"]).to eq(%w[bread brioche])
    end

    it "maps EXIF camera fields, preferring FNumber and ISO" do
      expect(mapped["exif:Make"]).to eq("Canon")
      expect(mapped["exif:Model"]).to eq("EOS R5")
      expect(mapped["exif:FocalLength"]).to eq("50.0 mm")
      expect(mapped["exif:ApertureValue"]).to eq(2.8)
      expect(mapped["exif:ISOSpeedRatings"]).to eq(100)
      expect(mapped["exif:ShutterSpeedValue"]).to eq("1/200")
    end

    it "omits properties with no embedded source" do
      expect(mapped).not_to have_key("Iptc4xmpCore:Source")
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
      expect(described_class.call(symbolised)["exif:Make"]).to eq("Nikon")
    end

    it "falls back to flat top-level properties when no grouped payload exists" do
      flat = {
        "camera_make" => "NIKON CORPORATION",
        "camera_model" => "NIKON D850",
        "date_taken" => "2024-05-01",
      }
      result = described_class.call(flat)
      expect(result["exif:Make"]).to eq("NIKON CORPORATION")
      expect(result["exif:Model"]).to eq("NIKON D850")
      expect(result["dc:date"]).to eq("2024-05-01")
    end

    it "prefers grouped embedded metadata over flat fallbacks" do
      combined = {
        "camera_make" => "NIKON CORPORATION",
        "embedded_metadata" => { "EXIF" => { "Make" => "Canon" } },
      }
      expect(described_class.call(combined)["exif:Make"]).to eq("Canon")
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
        expect(result["Iptc4xmpCore:Headline"]).to eq("846085_S_SpeciallySelected_GiantBriocheBuns_NP_S")
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
  end
end
