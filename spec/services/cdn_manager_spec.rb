require "rails_helper"

RSpec.describe CdnManager do
  describe ".adapter" do
    it "prefers the active database configuration" do
      active_config = instance_double(CdnConfiguration, provider: "fastly", settings: { "api_key" => "secret" })
      allow(CdnConfiguration).to receive(:find_by).with(is_active: true).and_return(active_config)
      adapter = instance_double(CdnAdapters::FastlyAdapter)
      allow(CdnAdapters::FastlyAdapter).to receive(:new).with({ api_key: "secret" }).and_return(adapter)

      expect(described_class.adapter).to eq(adapter)
    end

    it "falls back to yaml configuration when no database config exists" do
      allow(CdnConfiguration).to receive(:find_by).with(is_active: true).and_return(nil)
      adapter = instance_double(CdnAdapters::CloudflareAdapter)
      allow(Rails.application).to receive(:config_for).with(:cdn_settings).and_return(
        active_provider: "cloudflare",
        cloudflare: { token: "secret" },
      )
      allow(CdnAdapters::CloudflareAdapter).to receive(:new).with({ token: "secret" }).and_return(adapter)

      expect(described_class.adapter).to eq(adapter)
    end

    it "raises when no configuration exists" do
      allow(CdnConfiguration).to receive(:find_by).with(is_active: true).and_return(nil)
      allow(Rails.application).to receive(:config_for).with(:cdn_settings).and_return({})

      expect { described_class.adapter }.to raise_error("FATAL: No CDN configured in Database or YAML.")
    end
  end

  describe "delegation helpers" do
    let(:adapter) { instance_double("CdnAdapter", sync_metadata: true, purge_tag: true, purge_batch: true) }

    before do
      allow(described_class).to receive(:adapter).and_return(adapter)
    end

    it "delegates metadata sync to the adapter" do
      expect(described_class.sync_metadata("asset-1", { title: "Hero" })).to be(true)
      expect(adapter).to have_received(:sync_metadata).with("asset-1", title: "Hero")
    end

    it "delegates single-tag purge to the adapter" do
      described_class.purge_tag("hero", soft_purge: false)

      expect(adapter).to have_received(:purge_tag).with("hero", soft_purge: false)
    end

    it "delegates batch purge to the adapter" do
      described_class.purge_batch(%w[hero promo])

      expect(adapter).to have_received(:purge_batch).with(%w[hero promo], soft_purge: true)
    end
  end
end
