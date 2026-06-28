# frozen_string_literal: true

require "rails_helper"

RSpec.describe AssetProvenanceRecord, type: :model do
  describe "validations" do
    subject { create(:asset_provenance_record) }

    it { is_expected.to be_valid }

    it "rejects an unknown manifest_status" do
      subject.manifest_status = "supervalid"
      expect(subject).not_to be_valid
      expect(subject.errors[:manifest_status]).to be_present
    end

    it "accepts every valid manifest_status" do
      AssetProvenanceRecord::MANIFEST_STATUSES.each do |s|
        subject.manifest_status = s
        expect(subject).to be_valid, "expected #{s} to be valid"
      end
    end

    it "enforces uniqueness on asset_id" do
      existing = create(:asset_provenance_record)
      dup = build(:asset_provenance_record, asset: existing.asset)
      expect(dup).not_to be_valid
      expect(dup.errors[:asset_id]).to be_present
    end
  end

  describe "scopes" do
    let!(:verified)    { create(:asset_provenance_record, :verified) }
    let!(:ai_mod)      { create(:asset_provenance_record, :ai_modified) }
    let!(:ai_gen)      { create(:asset_provenance_record, :ai_generated) }
    let!(:missing)     { create(:asset_provenance_record, :missing) }
    let!(:invalid_rec) { create(:asset_provenance_record, :invalid) }
    let!(:signed)      { create(:asset_provenance_record, :signed) }
    let!(:unchecked)   { create(:asset_provenance_record) }

    it ".verified returns only verified records" do
      expect(described_class.verified).to contain_exactly(verified)
    end

    it ".ai_modified returns records with is_ai_modified == true" do
      expect(described_class.ai_modified).to contain_exactly(ai_mod, ai_gen)
    end

    it ".ai_flagged returns ai_generated and ai_modified" do
      expect(described_class.ai_flagged).to contain_exactly(ai_mod, ai_gen)
    end

    it ".missing returns missing records" do
      expect(described_class.missing).to contain_exactly(missing)
    end

    it ".invalid_manifest returns invalid records" do
      expect(described_class.invalid_manifest).to contain_exactly(invalid_rec)
    end

    it ".signed returns signed records" do
      expect(described_class.signed).to contain_exactly(signed)
    end

    it ".needs_review returns missing, invalid, error" do
      error_rec = create(:asset_provenance_record, :error)
      expect(described_class.needs_review).to contain_exactly(missing, invalid_rec, error_rec)
    end
  end

  describe "instance helpers" do
    it "#ai_flagged? is true for ai_generated and ai_modified" do
      expect(build(:asset_provenance_record, :ai_generated).ai_flagged?).to be(true)
      expect(build(:asset_provenance_record, :ai_modified).ai_flagged?).to be(true)
      expect(build(:asset_provenance_record, :verified).ai_flagged?).to be(false)
    end

    it "#needs_attention? is true for missing, invalid, error" do
      expect(build(:asset_provenance_record, :missing).needs_attention?).to be(true)
      expect(build(:asset_provenance_record, :invalid).needs_attention?).to be(true)
      expect(build(:asset_provenance_record, :verified).needs_attention?).to be(false)
    end

    it "#verified? returns true only for verified status" do
      expect(build(:asset_provenance_record, :verified).verified?).to be(true)
      expect(build(:asset_provenance_record, :missing).verified?).to be(false)
    end
  end
end
