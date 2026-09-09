# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixityCheck do
  let(:asset)   { create(:asset) }
  let(:version) { create(:asset_version, asset: asset) }

  def check(status)
    described_class.new(asset: asset, asset_version: version, status: status, checked_at: Time.current)
  end

  it "accepts only the four known verdicts" do
    described_class::STATUSES.each { |status| expect(check(status)).to be_valid }
    expect(check("probably_fine")).not_to be_valid
  end

  it "requires a timestamp, because the value of a check is its date" do
    record = check("passed")
    record.checked_at = nil

    expect(record).not_to be_valid
  end

  describe "#conclusive?" do
    it "excludes unreadable, which never reached a verdict about the bytes" do
      expect(check("passed")).to be_conclusive
      expect(check("failed")).to be_conclusive
      expect(check("missing")).to be_conclusive
      expect(check("unreadable")).not_to be_conclusive
    end
  end

  describe "#passed?" do
    it "is true only for an actual digest match" do
      expect(check("passed")).to be_passed
      expect(check("missing")).not_to be_passed
    end
  end

  describe "scopes" do
    it "treats a missing object as failing, but not an unreadable one" do
      failed     = check("failed").tap(&:save!)
      missing    = check("missing").tap(&:save!)
      check("unreadable").save!

      expect(described_class.failing).to contain_exactly(failed, missing)
    end

    it "orders recent newest first" do
      old = check("passed").tap { |c| c.checked_at = 2.days.ago }.tap(&:save!)
      new = check("passed").tap(&:save!)

      expect(described_class.recent.to_a).to eq([ new, old ])
    end
  end
end
