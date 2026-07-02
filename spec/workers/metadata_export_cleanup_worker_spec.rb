require "rails_helper"

RSpec.describe MetadataExportCleanupWorker, type: :worker do
  it "destroys expired exports and purges attached files" do
    export = create(:metadata_export, :expired)
    export.files.attach(io: StringIO.new("csv"), filename: "export.csv", content_type: "text/csv")

    expect { described_class.new.perform }.to change(MetadataExport, :count).by(-1)
    expect(MetadataExport.exists?(export.id)).to be(false)
  end

  it "logs and continues when a single export cleanup fails" do
    expired = class_double(MetadataExport).as_stubbed_const
    export = instance_double(MetadataExport, id: 123, files: double(attached?: false), destroy: nil)
    allow(expired).to receive_message_chain(:expired, :find_each).and_yield(export)
    allow(export).to receive(:destroy).and_raise(StandardError, "cannot destroy")

    expect { described_class.new.perform }.not_to raise_error
  end
end
