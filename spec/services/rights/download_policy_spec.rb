require "rails_helper"

RSpec.describe Rights::DownloadPolicy do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)  { create(:user) }
  let(:admin) { create(:user, :admin) }

  def asset_with(terms: "public_domain", expires_at: nil)
    create(:asset, user: user, usage_terms: terms, license_expires_at: expires_at)
  end

  describe "argument validation" do
    it "rejects an unknown audience" do
      expect { described_class.for(asset_with, audience: :partner) }
        .to raise_error(ArgumentError, /unknown audience/)
    end

    it "rejects an unknown purpose" do
      expect { described_class.for(asset_with, audience: :internal, purpose: :print) }
        .to raise_error(ArgumentError, /unknown purpose/)
    end
  end

  describe "the external audience" do
    it "refuses an internal-only asset for download" do
      decision = described_class.for(asset_with(terms: "internal_only"), audience: :external)

      expect(decision).to be_denied
      expect(decision.code).to eq(:not_externally_distributable)
    end

    it "refuses an internal-only asset for viewing too" do
      # Showing a guest an internal asset *is* the disclosure. There is no
      # "they only looked at it" for someone outside the organisation.
      decision = described_class.for(
        asset_with(terms: "internal_only"), audience: :external, purpose: :view
      )

      expect(decision).to be_denied
      expect(decision.code).to eq(:not_externally_distributable)
    end

    it "allows an editorial-only asset" do
      # "Editorial Use Only" restricts the *context* of use, not whether the
      # asset may leave the organisation — an editorial image is published.
      # Commercial-use limits are a separate concern from distribution.
      expect(described_class.for(asset_with(terms: "editorial_only"), audience: :external))
        .to be_allowed
    end

    it "allows a distributable asset with no expiry" do
      expect(described_class.for(asset_with(terms: "public_domain"), audience: :external))
        .to be_allowed
    end

    it "refuses a distributable asset whose licence has lapsed" do
      decision = described_class.for(
        asset_with(terms: "public_domain", expires_at: 1.day.ago), audience: :external
      )

      expect(decision).to be_denied
      expect(decision.code).to eq(:license_expired)
    end

    it "allows a distributable asset whose licence is still current" do
      expect(described_class.for(
        asset_with(terms: "public_domain", expires_at: 1.year.from_now), audience: :external
      )).to be_allowed
    end

    it "does not let an administrator bypass the external check" do
      # The admin creating a share link is not the person on the other end of
      # it. Their privileges are not transitive to the recipient.
      decision = described_class.for(
        asset_with(terms: "internal_only"), audience: :external, user: admin
      )

      expect(decision).to be_denied
    end

    it "does not let an administrator bypass external expiry" do
      decision = described_class.for(
        asset_with(terms: "public_domain", expires_at: 1.day.ago),
        audience: :external, user: admin
      )

      expect(decision).to be_denied
      expect(decision.code).to eq(:license_expired)
    end

    it "names the restriction in the message" do
      decision = described_class.for(asset_with(terms: "internal_only"), audience: :external)

      expect(decision.message).to include("Internal Use Only")
    end
  end

  describe "the internal audience" do
    it "always allows viewing, even for an internal-only asset" do
      expect(described_class.for(
        asset_with(terms: "internal_only"), audience: :internal, purpose: :view, user: user
      )).to be_allowed
    end

    it "always allows viewing, even when the licence has lapsed" do
      # Blocking inline delivery would blank every thumbnail in the application
      # the day a licence expired, which is how a safety control gets disabled.
      expect(described_class.for(
        asset_with(expires_at: 1.day.ago), audience: :internal, purpose: :view, user: user
      )).to be_allowed
    end

    it "allows downloading an internal-only asset" do
      # Usage terms answer "may this leave the organisation" — internal staff
      # taking an internal copy is exactly what internal_only is *for*.
      expect(described_class.for(
        asset_with(terms: "internal_only"), audience: :internal, purpose: :download, user: user
      )).to be_allowed
    end

    it "refuses to export an asset whose licence has lapsed" do
      decision = described_class.for(
        asset_with(expires_at: 1.day.ago), audience: :internal, purpose: :download, user: user
      )

      expect(decision).to be_denied
      expect(decision.code).to eq(:license_expired)
    end

    it "lets an administrator export a lapsed asset" do
      # Somebody has to be able to retrieve it in order to archive or replace it.
      expect(described_class.for(
        asset_with(expires_at: 1.day.ago), audience: :internal, purpose: :download, user: admin
      )).to be_allowed
    end

    it "allows export when the licence is still current" do
      expect(described_class.for(
        asset_with(expires_at: 1.day.from_now), audience: :internal, purpose: :download, user: user
      )).to be_allowed
    end
  end

  describe "expiry boundary" do
    it "treats a bare expiry date as lasting to the end of that day" do
      asset = create(:asset, user: user, usage_terms: "public_domain",
                             license_expires_at: "2026-06-30")

      travel_to(Time.zone.parse("2026-06-30 23:00")) do
        expect(described_class.for(asset, audience: :external)).to be_allowed
      end

      travel_to(Time.zone.parse("2026-07-01 00:30")) do
        expect(described_class.for(asset, audience: :external)).to be_denied
      end
    end

    it "judges against the supplied moment rather than now" do
      asset = asset_with(expires_at: 1.day.from_now)

      expect(described_class.for(asset, audience: :external, at: 1.year.from_now)).to be_denied
    end
  end

  describe ".allow?" do
    it "reduces the decision to a boolean" do
      expect(described_class.allow?(asset_with, audience: :external)).to be(true)
      expect(described_class.allow?(asset_with(terms: "internal_only"), audience: :external))
        .to be(false)
    end
  end

  describe ".partition" do
    it "splits the set and keeps each refusal's reason attached" do
      ok        = asset_with(terms: "public_domain")
      restricted = asset_with(terms: "internal_only")
      lapsed    = asset_with(terms: "public_domain", expires_at: 2.days.ago)

      permitted, refused = described_class.partition(
        [ ok, restricted, lapsed ], audience: :external
      )

      expect(permitted).to eq([ ok ])
      expect(refused.map { |r| r[:asset] }).to contain_exactly(restricted, lapsed)
      expect(refused.map { |r| r[:code] })
        .to contain_exactly(:not_externally_distributable, :license_expired)
      expect(refused.map { |r| r[:message] }).to all(be_present)
    end

    it "returns everything when nothing is restricted" do
      assets = [ asset_with, asset_with ]

      permitted, refused = described_class.partition(assets, audience: :external)

      expect(permitted).to match_array(assets)
      expect(refused).to be_empty
    end
  end

  describe "a nil asset" do
    it "does not deny" do
      # Absence is somebody else's error to report — a 404, not a 403. Returning
      # a denial here would turn "this does not exist" into "you may not have
      # this", which is both wrong and confusing.
      expect(described_class.for(nil, audience: :external)).to be_allowed
    end
  end
end
