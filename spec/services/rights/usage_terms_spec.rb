require "rails_helper"

RSpec.describe Rights::UsageTerms do
  describe ".normalise" do
    it "passes canonical codes through unchanged" do
      described_class::CODES.each do |code|
        expect(described_class.normalise(code)).to eq(code)
      end
    end

    it "collapses the spellings that the old free-text field allowed to diverge" do
      # Every one of these was a distinct value in `properties["usage_terms"]`,
      # and only the exact literal "Internal Use Only" was treated as internal.
      [ "Internal Use Only", "internal use only", "INTERNAL-USE-ONLY", "  Internal_Only  ", "internal" ]
        .each do |spelling|
          expect(described_class.normalise(spelling)).to eq("internal_only"),
                                                         "expected #{spelling.inspect} to normalise to internal_only"
        end
    end

    it "maps legacy and abbreviated vocabulary onto canonical codes" do
      expect(described_class.normalise("Licensed")).to eq("rights_managed")
      expect(described_class.normalise("RM")).to eq("rights_managed")
      expect(described_class.normalise("Royalty-Free")).to eq("royalty_free")
      expect(described_class.normalise("RF")).to eq("royalty_free")
      expect(described_class.normalise("EDITORIAL")).to eq("editorial_only")
      expect(described_class.normalise("CC0")).to eq("public_domain")
      expect(described_class.normalise("All Rights Reserved")).to eq("internal_only")
    end

    it "falls back to the most restrictive term for anything it cannot read" do
      # The direction of this fallback is the whole point: an unreadable rights
      # statement must never be mistaken for permission to distribute.
      [ "see contract with agency", "ask legal", "???", "", "   ", nil ].each do |value|
        expect(described_class.normalise(value)).to eq("internal_only")
        expect(described_class.externally_distributable?(described_class.normalise(value))).to be(false)
      end
    end

    it "accepts symbols as readily as strings" do
      expect(described_class.normalise(:royalty_free)).to eq("royalty_free")
    end
  end

  describe ".recognised?" do
    it "distinguishes an understood term from one that merely defaulted" do
      expect(described_class.recognised?("Licensed")).to be(true)
      expect(described_class.recognised?("Internal Use Only")).to be(true)

      # Both of the following normalise to internal_only, but only one of them
      # was actually understood — the caller needs to tell them apart to know
      # whether the original text is worth preserving.
      expect(described_class.recognised?("see contract")).to be(false)
      expect(described_class.recognised?(nil)).to be(false)
    end
  end

  describe ".externally_distributable?" do
    it "permits external distribution only for terms that grant it" do
      expect(described_class.externally_distributable?("internal_only")).to be(false)
      expect(described_class.externally_distributable?("editorial_only")).to be(true)
      expect(described_class.externally_distributable?("rights_managed")).to be(true)
      expect(described_class.externally_distributable?("royalty_free")).to be(true)
      expect(described_class.externally_distributable?("public_domain")).to be(true)
    end

    it "refuses a code outside the vocabulary rather than raising" do
      expect(described_class.externally_distributable?("something_invented")).to be(false)
      expect(described_class.externally_distributable?(nil)).to be(false)
    end
  end

  describe ".label" do
    it "returns the English label for each code" do
      expect(described_class.label("rights_managed")).to eq("Rights Managed")
      expect(described_class.label("internal_only")).to eq("Internal Use Only")
    end

    it "falls back to the default label for an unknown code" do
      expect(described_class.label("nonsense")).to eq("Internal Use Only")
    end
  end

  describe "the vocabulary itself" do
    it "keeps the default among the codes and restrictive" do
      expect(described_class::CODES).to include(described_class::DEFAULT)
      expect(described_class.externally_distributable?(described_class::DEFAULT)).to be(false)
    end

    it "maps every synonym onto a real code" do
      expect(described_class::SYNONYMS.values.uniq - described_class::CODES).to be_empty
    end

    it "recognises every canonical code as itself" do
      # Regression: editorial_only was a valid code with no matching synonym,
      # so a client sending the exact code was silently downgraded to
      # internal_only. LOOKUP now guarantees the identity mapping.
      described_class::CODES.each do |code|
        expect(described_class.recognised?(code)).to be(true), "#{code} does not map to itself"
        expect(described_class.normalise(code)).to eq(code)
      end
    end
  end
end
