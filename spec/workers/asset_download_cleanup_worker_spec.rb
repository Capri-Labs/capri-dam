require "rails_helper"

RSpec.describe AssetDownloadCleanupWorker, type: :worker do
  it "destroys expired downloads and purges attached ZIP files" do
    download = create(:asset_download, :expired)
    download.zip_file.attach(io: StringIO.new("zip bytes"), filename: "download.zip", content_type: "application/zip")

    expect { described_class.new.perform }.to change(AssetDownload, :count).by(-1)
    expect(AssetDownload.exists?(download.id)).to be(false)
  end

  it "logs and continues when a single download cleanup fails" do
    expired = class_double(AssetDownload).as_stubbed_const
    download = instance_double(AssetDownload, id: 123, zip_file: double(attached?: false), destroy: nil)
    allow(expired).to receive_message_chain(:expired, :find_each).and_yield(download)
    allow(download).to receive(:destroy).and_raise(StandardError, "cannot destroy")

    expect { described_class.new.perform }.not_to raise_error
  end
end
