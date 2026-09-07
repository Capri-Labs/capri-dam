require "rails_helper"

RSpec.describe Rights::LicenseExpiry do
  describe ".parse" do
    it "reads an ISO 8601 timestamp" do
      expect(described_class.parse("2026-12-31T10:00:00Z")).to eq(Time.utc(2026, 12, 31, 10, 0, 0))
    end

    it "reads a bare ISO 8601 date as the end of that day" do
      # A licence stated to expire on 31 December is good through 31 December.
      # Reading it as midnight would retire the asset a day early, every time.
      parsed = described_class.parse("2026-12-31")

      expect(parsed.to_date).to eq(Date.new(2026, 12, 31))
      expect(parsed.hour).to eq(23)
      expect(parsed.min).to eq(59)
    end

    it "accepts Time, Date and DateTime objects" do
      expect(described_class.parse(Time.utc(2026, 5, 1, 12))).to eq(Time.utc(2026, 5, 1, 12))
      expect(described_class.parse(Date.new(2026, 5, 1)).to_date).to eq(Date.new(2026, 5, 1))
      expect(described_class.parse(DateTime.new(2026, 5, 1, 12))).to eq(Time.utc(2026, 5, 1, 12))
    end

    it "returns nil for absent values" do
      expect(described_class.parse(nil)).to be_nil
      expect(described_class.parse("")).to be_nil
      expect(described_class.parse("   ")).to be_nil
    end

    context "on the inputs that made the previous Time.zone.parse implementation unsafe" do
      it "returns nil for a year-only value instead of raising" do
        # Time.zone.parse("2024") raises ArgumentError, which aborted
        # Collection#compliance_violations for an entire collection.
        expect { Time.zone.parse("2024") }.to raise_error(ArgumentError)
        expect(described_class.parse("2024")).to be_nil
      end

      it "refuses a bare number instead of reading it as an ancient year" do
        # Time.zone.parse("12345") returns the year 12 — a typo becomes an asset
        # that has been expired for two millennia.
        expect(Time.zone.parse("12345").year).to eq(12)
        expect(described_class.parse("12345")).to be_nil
      end

      it "rejects an impossible calendar date instead of rolling it forward" do
        # Time.zone.parse("2026-02-30") silently returns 2 March.
        expect(Time.zone.parse("2026-02-30").to_date).to eq(Date.new(2026, 3, 2))
        expect(described_class.parse("2026-02-30")).to be_nil
      end

      it "returns nil for free text that happens to sit in the field" do
        [ "Internal Use Only", "TBD", "N/A", "soon", "see contract" ].each do |junk|
          expect(described_class.parse(junk)).to be_nil
        end
      end
    end

    it "rejects locale-ambiguous slash formats rather than guessing" do
      # 01/02/2026 is a different day in London and New York, and a rights
      # expiry is not a field to be wrong about by ten months. Rejected input
      # is preserved verbatim by the caller, never coerced.
      expect(described_class.parse("31/12/2026")).to be_nil
      expect(described_class.parse("01/02/2026")).to be_nil
      expect(described_class.parse("Dec 31 2026")).to be_nil
    end
  end

  describe ".malformed?" do
    it "is false for absent values, which are a legitimate state" do
      expect(described_class.malformed?(nil)).to be(false)
      expect(described_class.malformed?("")).to be(false)
      expect(described_class.malformed?("   ")).to be(false)
    end

    it "is false for anything it can parse" do
      expect(described_class.malformed?("2026-12-31")).to be(false)
      expect(described_class.malformed?(Time.current)).to be(false)
    end

    it "is true for a value that was supplied but could not be read" do
      # "no expiry recorded" and "an expiry we failed to read" have opposite
      # risk profiles, so they must not collapse into the same nil.
      expect(described_class.malformed?("2024")).to be(true)
      expect(described_class.malformed?("31/12/2026")).to be(true)
      expect(described_class.malformed?("whenever")).to be(true)
    end
  end

  describe ".serialise" do
    it "round-trips through parse" do
      original = "2026-12-31T10:00:00Z"
      expect(described_class.parse(described_class.serialise(described_class.parse(original))))
        .to eq(Time.utc(2026, 12, 31, 10, 0, 0))
    end

    it "returns nil for nil" do
      expect(described_class.serialise(nil)).to be_nil
    end
  end
end
