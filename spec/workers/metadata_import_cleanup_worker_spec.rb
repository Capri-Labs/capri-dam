require "rails_helper"

RSpec.describe MetadataImportCleanupWorker, type: :worker do
  it "destroys expired imports and purges attached files" do
    import = create(:metadata_import, :expired)
    import.source_file.attach(io: StringIO.new("source"), filename: "source.csv", content_type: "text/csv")
    import.result_file.attach(io: StringIO.new("result"), filename: "result.csv", content_type: "text/csv")

    expect { described_class.new.perform }.to change(MetadataImport, :count).by(-1)
    expect(MetadataImport.exists?(import.id)).to be(false)
  end

  it "logs and continues when a single import cleanup fails" do
    expired = class_double(MetadataImport).as_stubbed_const
    import = instance_double(
      MetadataImport,
      id: 456,
      source_file: double(attached?: false),
      result_file: double(attached?: false),
      destroy: nil
    )
    allow(expired).to receive_message_chain(:expired, :find_each).and_yield(import)
    allow(import).to receive(:destroy).and_raise(StandardError, "cannot destroy")

    expect { described_class.new.perform }.not_to raise_error
  end
end
