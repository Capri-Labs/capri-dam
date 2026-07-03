require "rails_helper"

RSpec.describe PersonalAccessToken, type: :model do
  let(:user) { create(:user) }

  # ── .generate_for ───────────────────────────────────────────────────────────

  describe ".generate_for" do
    it "returns a token record and a raw string prefixed with 'dat_'" do
      pat, raw = PersonalAccessToken.generate_for(user, name: "Test")
      expect(pat).to be_persisted
      expect(raw).to start_with("dat_")
      expect(raw.length).to eq(4 + 32)   # "dat_" + 32 hex chars
    end

    it "stores a SHA-256 digest, not the raw token" do
      pat, raw = PersonalAccessToken.generate_for(user, name: "Test")
      expect(pat.token_digest).to eq(Digest::SHA256.hexdigest(raw))
      expect(pat.token_digest).not_to include(raw)
    end

    it "stores the last 4 characters" do
      pat, raw = PersonalAccessToken.generate_for(user, name: "Test")
      expect(pat.last_four).to eq(raw.last(4))
    end

    it "sets active: true by default" do
      pat, _ = PersonalAccessToken.generate_for(user, name: "Test")
      expect(pat).to be_active
    end

    it "respects an explicit expires_at" do
      exp = 1.year.from_now
      pat, _ = PersonalAccessToken.generate_for(user, name: "Test", expires_at: exp)
      expect(pat.expires_at).to be_within(1.second).of(exp)
    end
  end

  # ── .authenticate ────────────────────────────────────────────────────────────

  describe ".authenticate" do
    let!(:pat) { PersonalAccessToken.generate_for(user, name: "CI").then { |p, _| p } }
    let!(:raw) { PersonalAccessToken.generate_for(user, name: "CI2").then { |_, r| r } }

    it "returns the user for a valid token" do
      _, raw_token = PersonalAccessToken.generate_for(user, name: "Auth Test")
      expect(PersonalAccessToken.authenticate(raw_token)).to eq(user)
    end

    it "returns nil for an unknown token" do
      expect(PersonalAccessToken.authenticate("dat_#{SecureRandom.hex(16)}")).to be_nil
    end

    it "returns nil for a revoked token" do
      pat, raw_token = PersonalAccessToken.generate_for(user, name: "Revoke Test")
      pat.revoke!
      expect(PersonalAccessToken.authenticate(raw_token)).to be_nil
    end

    it "returns nil for an expired token" do
      pat, raw_token = PersonalAccessToken.generate_for(user, name: "Expired", expires_at: 1.hour.ago)
      expect(PersonalAccessToken.authenticate(raw_token)).to be_nil
    end

    it "returns nil for a string that doesn't start with 'dat_'" do
      expect(PersonalAccessToken.authenticate("ghp_abc123")).to be_nil
    end

    it "returns nil for a nil token" do
      expect(PersonalAccessToken.authenticate(nil)).to be_nil
    end

    it "touches last_used_at on a successful auth" do
      pat, raw_token = PersonalAccessToken.generate_for(user, name: "Used")
      expect { PersonalAccessToken.authenticate(raw_token) }
        .to change { pat.reload.last_used_at }.from(nil)
    end
  end

  # ── Validations ──────────────────────────────────────────────────────────────

  describe "validations" do
    it "requires a name" do
      pat = build(:personal_access_token, user: user, name: "")
      expect(pat).not_to be_valid
      expect(pat.errors[:name]).to be_present
    end

    it "rejects an unsupported scope" do
      pat = build(:personal_access_token, user: user, scopes: "superpower")
      expect(pat).not_to be_valid
    end

    it "enforces uniqueness of token_digest" do
      existing, _ = PersonalAccessToken.generate_for(user, name: "Original")
      duplicate = build(:personal_access_token, user: user, token_digest: existing.token_digest)
      expect(duplicate).not_to be_valid
    end
  end

  # ── #revoke! ─────────────────────────────────────────────────────────────────

  describe "#revoke!" do
    it "sets active to false without deleting the record" do
      pat, _ = PersonalAccessToken.generate_for(user, name: "Revokable")
      expect { pat.revoke! }.to change { pat.reload.active }.from(true).to(false)
      expect(PersonalAccessToken.find(pat.id)).to be_present
    end
  end
end
