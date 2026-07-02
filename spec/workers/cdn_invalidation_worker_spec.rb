require "rails_helper"

RSpec.describe CdnInvalidationWorker, type: :worker do
  before { allow(CdnManager).to receive(:purge_tag) }

  it "purges an asset tag and logs the asset path branch" do
    described_class.new.perform("asset", "asset-uuid")

    expect(CdnManager).to have_received(:purge_tag).with("asset-asset-uuid")
  end

  it "purges a folder target and returns when the folder is missing" do
    folder = create(:folder)
    create(:asset, folder: folder)

    expect { described_class.new.perform("folder", folder.id) }.not_to raise_error
    expect { described_class.new.perform("folder", "missing") }.not_to raise_error
    expect(CdnManager).to have_received(:purge_tag).with("folder-#{folder.id}")
  end

  it "warns for unknown targets after purging the tag" do
    expect(Rails.logger).to receive(:warn).with(a_string_including("Unknown CDN purge target"))

    described_class.new.perform("mystery", 123)

    expect(CdnManager).to have_received(:purge_tag).with("mystery-123")
  end
end
