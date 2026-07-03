require "rails_helper"

RSpec.describe DataHealthRemediationWorker, type: :worker do
  it "queues a duplicate scan unless one is already running" do
    allow(Setting).to receive(:get).and_return("")
    allow(Setting).to receive(:set)
    allow(DuplicateRepositoryScanWorker).to receive(:perform_async)

    described_class.new.perform("duplicates", 1)

    expect(Setting).to have_received(:set).with("duplicate_manager_scan_status", "queued")
    expect(DuplicateRepositoryScanWorker).to have_received(:perform_async)
  end

  it "skips duplicate scans already queued or running" do
    allow(Setting).to receive(:get).with("duplicate_manager_scan_status").and_return("running")
    allow(Setting).to receive(:get).with("duplicate_manager_scan_progress").and_return(
      { processed: 1, total: 2, updated_at: Time.current.iso8601 }
    )
    allow(Setting).to receive(:set)
    allow(DuplicateRepositoryScanWorker).to receive(:perform_async)

    described_class.new.perform("duplicates", 1)

    expect(Setting).not_to have_received(:set)
    expect(DuplicateRepositoryScanWorker).not_to have_received(:perform_async)
  end

  it "queues missing metadata analysis for active connectors and handles none" do
    connector = create(:system_connector, status: "active")
    create(:system_connector, status: "inactive")
    allow(PreFlightAnalysisWorker).to receive(:perform_async)

    described_class.new.perform("missing_metadata", 1)
    SystemConnector.where(status: "active").update_all(status: "inactive")
    described_class.new.perform("missing_metadata", 1)

    expect(PreFlightAnalysisWorker).to have_received(:perform_async).with(connector.id).once
  end

  it "flags assets missing copyright without touching copyrighted assets" do
    missing = create(:asset, properties: {})
    present = create(:asset, properties: { "copyright" => "Acme" })

    described_class.new.perform("copyright", 1)

    expect(missing.reload.properties["tdm_copyright_flagged"]).to eq(true)
    expect(present.reload.properties).not_to have_key("tdm_copyright_flagged")
  end

  it "logs unknown debt types and reraises remediation errors" do
    expect { described_class.new.perform("unknown", 1) }.not_to raise_error

    allow(Setting).to receive(:get).and_raise(StandardError, "settings unavailable")
    expect { described_class.new.perform("duplicates", 1) }.to raise_error(StandardError, "settings unavailable")
  end
end
