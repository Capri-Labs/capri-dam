require "rails_helper"

RSpec.describe MigrationCommitWorker, type: :worker do
  let(:user) { create(:user) }
  let(:batch) { create(:ingestion_batch, status: :review_needed, initiated_by_id: user.id, total_count: 1) }

  it "returns early for missing batches and invalid statuses" do
    initializing = create(:ingestion_batch, status: :initializing)

    expect { described_class.new.perform(0) }.not_to raise_error
    expect { described_class.new.perform(initializing.id) }.not_to change(Asset, :count)
  end

  it "commits ready items into assets and versions, then queues the next chunk" do
    item = create(:ingestion_item, ingestion_batch: batch, status: :ready_for_import, clean_properties: {
      "title" => "Hero", "description" => "Desc", "tags" => [ "tag" ], "campaign" => "Summer"
    })
    allow(described_class).to receive(:perform_async)
    allow_any_instance_of(Asset).to receive(:broadcast_for_embedding)

    expect { described_class.new.perform(batch.id) }.to change(Asset, :count).by(1)

    asset = Asset.order(:created_at).last
    expect(asset.title).to eq("Hero")
    expect(asset.asset_versions.first.action_type).to eq("migration_import")
    expect(item.reload).to be_committed
    expect(batch.reload.committed_count).to eq(1)
    expect(described_class).to have_received(:perform_async).with(batch.id, described_class::COMMIT_CHUNK)
  end

  it "finalizes empty batches and queues the report worker" do
    batch.update!(status: :committed)
    allow(MigrationReportWorker).to receive(:perform_async)

    described_class.new.perform(batch.id)

    expect(batch.reload.completed_at).to be_present
    expect(MigrationReportWorker).to have_received(:perform_async).with(batch.id)
  end

  it "marks an item as errored when committing it fails" do
    item = create(:ingestion_item, ingestion_batch: batch, status: :ready_for_import)
    allow(Asset).to receive(:create!).and_raise(StandardError, "invalid asset")
    allow(described_class).to receive(:perform_async)

    expect { described_class.new.perform(batch.id) }.not_to raise_error
    expect(item.reload).to be_flagged_error
    expect(batch.reload.error_count).to eq(1)
  end
end
