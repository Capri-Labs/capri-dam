require "rails_helper"

# Rights normalisation on Asset: the typed `usage_terms` / `license_expires_at`
# columns and the legacy `properties` JSONB keys of the same name have to stay
# in agreement, because both are written by real code paths — the API and the
# admin UI write columns, while the bulk metadata editor, the XMP mapper and the
# migration importers write JSONB.
RSpec.describe Asset, "rights normalisation" do
  let(:user) { create(:user) }

  def build_asset(**attrs)
    build(:asset, user: user, **attrs)
  end

  describe "defaults" do
    it "starts internal-only, so an asset nobody classified cannot be distributed" do
      asset = create(:asset, user: user)

      expect(asset.usage_terms).to eq("internal_only")
      expect(asset.externally_distributable?).to be(false)
      expect(asset.license_expires_at).to be_nil
    end

    it "records no expiry rather than a sentinel date" do
      # "no expiry" and "unknown expiry" are different states and only the
      # former is representable; a sentinel would make them indistinguishable.
      asset = create(:asset, user: user)

      expect(asset.license_expired?).to be(false)
    end
  end

  describe "writing through properties" do
    it "canonicalises a free-text term into the column and back into the JSONB" do
      asset = create(:asset, user: user, properties: { "usage_terms" => "Royalty-Free" })

      expect(asset.usage_terms).to eq("royalty_free")
      expect(asset.properties["usage_terms"]).to eq("royalty_free")
    end

    it "collapses spellings that the old exact-literal comparison treated as different" do
      %w[Licensed licensed LICENSED rights-managed RM].each do |spelling|
        asset = create(:asset, user: user, properties: { "usage_terms" => spelling })
        expect(asset.usage_terms).to eq("rights_managed"), "#{spelling.inspect} did not normalise"
      end
    end

    it "falls back to internal-only for an unreadable term but keeps the original text" do
      asset = create(:asset, user: user, properties: { "usage_terms" => "see contract with agency" })

      expect(asset.usage_terms).to eq("internal_only")
      expect(asset.externally_distributable?).to be(false)
      # The importer's original reading is the only evidence of what the rights
      # were meant to say, so it is preserved rather than discarded.
      expect(asset.properties["usage_terms_raw"]).to eq("see contract with agency")
    end

    it "clears the preserved raw term once a readable one replaces it" do
      asset = create(:asset, user: user, properties: { "usage_terms" => "ask legal" })
      expect(asset.properties["usage_terms_raw"]).to be_present

      asset.update!(properties: asset.properties.merge("usage_terms" => "Public Domain"))

      expect(asset.usage_terms).to eq("public_domain")
      expect(asset.properties).not_to have_key("usage_terms_raw")
    end

    it "parses an ISO date into the typed column, ending at the close of that day" do
      asset = create(:asset, user: user, properties: { "license_expires_at" => "2026-12-31" })

      expect(asset.license_expires_at.to_date).to eq(Date.new(2026, 12, 31))
      expect(asset.license_expires_at.hour).to eq(23)
      expect(asset.properties["license_expires_at"]).to eq(asset.license_expires_at.iso8601)
    end
  end

  describe "writing through the columns" do
    it "mirrors a column write back into the JSONB the search facets read" do
      asset = create(:asset, user: user, usage_terms: "editorial_only")

      expect(asset.properties["usage_terms"]).to eq("editorial_only")
    end

    it "does not silently downgrade a canonical code it was handed directly" do
      # Regression: editorial_only had no entry in the synonym table, so the
      # exact code normalised to internal_only.
      Rights::UsageTerms::CODES.each do |code|
        asset = create(:asset, user: user, usage_terms: code)
        expect(asset.reload.usage_terms).to eq(code)
      end
    end

    it "serialises an expiry set on the column into the JSONB" do
      expiry = 30.days.from_now.change(usec: 0)
      asset  = create(:asset, user: user, license_expires_at: expiry)

      expect(asset.properties["license_expires_at"]).to eq(expiry.iso8601)
    end
  end

  describe "rejecting unreadable expiry dates" do
    # Each of these was silently accepted before, and each broke a different
    # reader downstream.
    {
      "2024"       => "raised ArgumentError inside Collection#compliance_violations",
      "12345"      => "was read as the year 12, i.e. permanently expired",
      "2026-02-30" => "was silently rolled forward to 2 March",
      "31/12/2026" => "is locale-ambiguous",
      "whenever"   => "is not a date at all",
    }.each do |value, why|
      it "refuses #{value.inspect}, which #{why}" do
        asset = build_asset(properties: { "license_expires_at" => value })

        expect(asset).not_to be_valid
        expect(asset.errors[:license_expires_at].join).to include("ISO 8601")
        expect(asset.license_expires_at).to be_nil
      end
    end

    it "keeps reporting invalid when validated repeatedly" do
      # The record must not mutate itself into validity: an object that fails
      # once and passes on the second call would let a save through.
      asset = build_asset(properties: { "license_expires_at" => "2024" })

      expect(asset.valid?).to be(false)
      expect(asset.valid?).to be(false)
      expect(asset.save).to be(false)
    end

    it "becomes valid once the value is corrected" do
      asset = build_asset(properties: { "license_expires_at" => "2024" })
      expect(asset).not_to be_valid

      asset.properties = asset.properties.merge("license_expires_at" => "2024-12-31")

      expect(asset).to be_valid
      expect(asset.license_expires_at.to_date).to eq(Date.new(2024, 12, 31))
    end

    it "treats a blank expiry as absent, not as malformed" do
      expect(build_asset(properties: { "license_expires_at" => "" })).to be_valid
      expect(build_asset(properties: { "license_expires_at" => nil })).to be_valid
    end

    it "rejects an unreadable string assigned straight to the column" do
      # Regression: Active Record casts an unparseable string to nil on the way
      # into a datetime attribute, so this arrived as "no expiry given",
      # nothing looked changed, and the save succeeded with the value silently
      # dropped. The custom writer captures the raw input so it can be reported.
      asset = build_asset
      asset.license_expires_at = "31/12/2026"

      expect(asset).not_to be_valid
      expect(asset.errors[:license_expires_at].join).to include("ISO 8601")
    end

    it "accepts a readable string assigned straight to the column" do
      asset = build_asset
      asset.license_expires_at = "2027-03-31"

      expect(asset).to be_valid
      expect(asset.license_expires_at.to_date).to eq(Date.new(2027, 3, 31))
    end
  end

  describe "precedence between the column and the properties key" do
    it "prefers a supplied term even when it equals the one already stored" do
      # Regression: precedence keyed on usage_terms_changed?, so assigning the
      # value the record already held was not a "change" and the caller's
      # clearest statement of intent lost to the metadata blob.
      asset = create(:asset, user: user, usage_terms: "internal_only")

      asset.update!(
        usage_terms: "internal_only",
        properties:  asset.properties.merge("usage_terms" => "public_domain")
      )

      expect(asset.reload.usage_terms).to eq("internal_only")
      expect(asset.properties["usage_terms"]).to eq("internal_only")
    end

    it "lets a later properties-only write take effect" do
      # The "was this supplied?" flag describes one write, not the record; if it
      # survived the save it would keep beating properties on every later save
      # of the same in-memory object.
      asset = create(:asset, user: user, usage_terms: "royalty_free")

      asset.update!(properties: asset.properties.merge("usage_terms" => "editorial_only"))

      expect(asset.reload.usage_terms).to eq("editorial_only")
    end

    it "clears an expiry set on the column without needing the properties key" do
      asset = create(:asset, user: user, license_expires_at: 30.days.from_now)

      asset.update!(license_expires_at: nil)

      expect(asset.reload.license_expires_at).to be_nil
      expect(asset.properties["license_expires_at"]).to be_nil
    end
  end

  describe "vocabulary enforcement" do
    it "rejects a term outside the vocabulary with a validation error" do
      asset = build_asset(usage_terms: "made_up_term")

      # normalise_rights folds the unknown value back to the default before
      # validation, so the record stays saveable — but it is never distributable.
      expect(asset).to be_valid
      expect(asset.usage_terms).to eq("internal_only")
      expect(asset.properties["usage_terms_raw"]).to eq("made_up_term")
    end

    it "is backed by a database CHECK constraint for writers that bypass the model" do
      asset = create(:asset, user: user)

      expect {
        ActiveRecord::Base.connection.execute(
          "UPDATE assets SET usage_terms = 'not_a_term' WHERE id = '#{asset.id}'"
        )
      }.to raise_error(ActiveRecord::StatementInvalid, /assets_usage_terms_in_vocabulary/)
    end
  end

  describe "#license_expired?" do
    it "is true only once the window has actually closed" do
      asset = create(:asset, user: user, license_expires_at: 1.hour.ago)
      expect(asset.license_expired?).to be(true)

      asset.update!(license_expires_at: 1.hour.from_now)
      expect(asset.license_expired?).to be(false)
    end

    it "judges against the moment supplied" do
      asset = create(:asset, user: user, license_expires_at: 5.days.from_now)

      expect(asset.license_expired?(10.days.from_now)).to be(true)
      expect(asset.license_expired?(1.day.from_now)).to be(false)
    end
  end

  describe "#externally_distributable?" do
    it "requires both permissive terms and a current licence" do
      # A royalty-free asset whose licence lapsed is no more distributable than
      # an internal-only one — the two conditions are ANDed, not ORed.
      expect(create(:asset, user: user, usage_terms: "royalty_free").externally_distributable?).to be(true)
      expect(create(:asset, user: user, usage_terms: "internal_only").externally_distributable?).to be(false)

      lapsed = create(:asset, user: user, usage_terms: "royalty_free", license_expires_at: 1.day.ago)
      expect(lapsed.externally_distributable?).to be(false)
    end
  end

  describe "scopes" do
    let!(:internal)  { create(:asset, user: user, usage_terms: "internal_only") }
    let!(:current)   { create(:asset, user: user, usage_terms: "royalty_free", license_expires_at: 60.days.from_now) }
    let!(:soon)      { create(:asset, user: user, usage_terms: "rights_managed", license_expires_at: 10.days.from_now) }
    let!(:lapsed)    { create(:asset, user: user, usage_terms: "rights_managed", license_expires_at: 3.days.ago) }
    let!(:no_expiry) { create(:asset, user: user, usage_terms: "public_domain") }

    it ".license_expired finds only assets past their date" do
      expect(Asset.license_expired).to contain_exactly(lapsed)
    end

    it ".license_current includes assets that never had an expiry" do
      expect(Asset.license_current).to include(internal, current, soon, no_expiry)
      expect(Asset.license_current).not_to include(lapsed)
    end

    it ".license_expiring_within is bounded at both ends" do
      # The old unbounded JSONB cast counted assets that had *already* expired
      # — and typo'd dates that landed in antiquity — as "expiring soon".
      expect(Asset.license_expiring_within(30.days)).to contain_exactly(soon)
      expect(Asset.license_expiring_within(30.days)).not_to include(lapsed)
    end

    it ".externally_distributable selects on terms alone" do
      expect(Asset.externally_distributable).to include(current, soon, lapsed, no_expiry)
      expect(Asset.externally_distributable).not_to include(internal)
    end
  end
end
