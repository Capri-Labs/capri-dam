require "rails_helper"

RSpec.describe CdnAdapters::NullAdapter, type: :service do
  subject(:adapter) { described_class.new }

  it "no-ops purge_tag and reports it was skipped" do
    expect(adapter.purge_tag("hero", soft_purge: false)).to eq(skipped: true, reason: "no_cdn_configured")
  end

  it "no-ops purge_batch and reports it was skipped" do
    expect(adapter.purge_batch(%w[hero promo])).to eq(skipped: true, reason: "no_cdn_configured")
  end

  it "no-ops sync_metadata and reports it was skipped" do
    expect(adapter.sync_metadata("asset-1", { title: "Hero" })).to eq(skipped: true, reason: "no_cdn_configured")
  end
end
