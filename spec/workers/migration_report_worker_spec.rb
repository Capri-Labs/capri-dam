require "rails_helper"

RSpec.describe MigrationReportWorker, type: :worker do
  let(:user) { create(:user, email: "report@example.com") }
  let(:batch) do
    create(:ingestion_batch,
      name: "Batch A",
      source_type: "aem",
      status: :committed,
      initiated_by_id: user.id,
      started_at: 10.minutes.ago,
      completed_at: Time.current,
      total_count: 3,
      committed_count: 1,
      duplicate_count: 1,
      error_count: 1)
  end

  it "returns early when the batch is missing" do
    expect { described_class.new.perform(0) }.not_to raise_error
  end

  it "persists a report snapshot, stores stats and notifies the initiator" do
    create(:ingestion_item, ingestion_batch: batch, status: :ready_for_import, clean_properties: { "title" => "Ready" })
    create(:ingestion_item, ingestion_batch: batch, status: :rejected)
    create(:ingestion_item, ingestion_batch: batch, status: :flagged_error, error_log: "bad")
    allow(EmailOrchestrator).to receive(:trigger)
    allow(ReportSnapshot).to receive(:create!).and_wrap_original do |method, attributes|
      method.call(attributes.merge(format: "csv"))
    end

    expect { described_class.new.perform(batch.id) }.to change(ReportSnapshot, :count).by(1)

    snapshot = ReportSnapshot.find(batch.reload.report_snapshot_id)
    expect(snapshot.parameters["stats"]).to include("committed" => 1, "duplicates_blocked" => 1, "errors" => 1)
    expect(EmailOrchestrator).to have_received(:trigger).with("migration_batch_complete", user.email, hash_including("batch"))
  end

  it "continues when snapshot persistence and email delivery fail" do
    allow(ReportSnapshot).to receive(:create!).and_raise(StandardError, "snapshot failed")
    allow(EmailOrchestrator).to receive(:trigger).and_raise(StandardError, "mail failed")

    expect { described_class.new.perform(batch.id) }.not_to raise_error
    expect(batch.reload.report_snapshot_id).to be_nil
  end
end
