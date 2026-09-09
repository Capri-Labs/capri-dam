# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fixity::Sampler do
  let(:asset) { create(:asset) }

  def version(properties, last_checked: nil, status: nil)
    v = create(:asset_version, asset: asset, properties: properties)
    v.update_columns(last_fixity_check_at: last_checked, fixity_status: status) if last_checked || status
    v
  end

  let(:verifiable_props) { { "checksum_sha256" => Digest::SHA256.hexdigest("x"), "storage_path" => "a/b.bin" } }

  describe ".verifiable" do
    it "requires both a digest and a path" do
      good    = version(verifiable_props)
      no_hash = version({ "storage_path" => "a/b.bin" })
      no_path = version({ "checksum_sha256" => "abc" })
      blank   = version({ "checksum_sha256" => "", "storage_path" => "a/b.bin" })

      expect(described_class.verifiable).to include(good)
      expect(described_class.verifiable).not_to include(no_hash, no_path, blank)
    end
  end

  describe ".unverifiable" do
    it "counts stored versions that have no digest to compare against" do
      no_hash = version({ "storage_path" => "a/b.bin" })
      version(verifiable_props)

      expect(described_class.unverifiable).to contain_exactly(no_hash)
    end
  end

  describe ".due" do
    it "drains never-checked versions before refreshing checked ones" do
      recent_but_stale = version(verifiable_props, last_checked: 200.days.ago, status: "passed")
      never_checked    = version(verifiable_props)

      expect(described_class.due.to_a).to eq([ never_checked, recent_but_stale ])
    end

    it "skips versions verified inside the recheck window" do
      fresh = version(verifiable_props, last_checked: 1.day.ago, status: "passed")

      expect(described_class.due).not_to include(fresh)
    end

    it "honours the budget, because a full sweep is an egress bill" do
      3.times { version(verifiable_props) }

      expect(described_class.due(limit: 2).count).to eq(2)
    end

    it "never returns a version it could not verify anyway" do
      no_hash = version({ "storage_path" => "a/b.bin" })

      expect(described_class.due).not_to include(no_hash)
    end
  end

  describe ".coverage" do
    it "reports the proportion with evidence behind it" do
      version(verifiable_props, last_checked: 1.day.ago, status: "passed")
      version(verifiable_props)
      version({ "storage_path" => "a/b.bin" })

      report = described_class.coverage

      expect(report[:verifiable]).to eq(2)
      expect(report[:checked]).to eq(1)
      expect(report[:never_checked]).to eq(1)
      expect(report[:unverifiable]).to eq(1)
      expect(report[:coverage_percent]).to eq(50.0)
      expect(report[:by_status]).to eq("passed" => 1)
    end

    it "returns zero rather than dividing by zero on an empty estate" do
      expect(described_class.coverage[:coverage_percent]).to eq(0.0)
    end
  end
end
