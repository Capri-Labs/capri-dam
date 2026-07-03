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

  it "commits ready items into the chosen destination folder when set" do
    folder = create(:folder, name: "Chosen", user: user)
    batch.update!(destination_folder: folder)
    create(:ingestion_item, ingestion_batch: batch, status: :ready_for_import, clean_properties: {
      "title" => "Hero", "campaign" => "Summer"
    })
    allow(described_class).to receive(:perform_async)
    allow_any_instance_of(Asset).to receive(:broadcast_for_embedding)

    described_class.new.perform(batch.id)

    expect(Asset.order(:created_at).last.folder).to eq(folder)
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

  it "falls back to the first user when initiated_by_id is missing" do
    fallback_user = create(:user)
    batch = create(:ingestion_batch, status: :review_needed, initiated_by_id: nil, total_count: 1)
    create(:ingestion_item, ingestion_batch: batch, status: :ready_for_import, clean_properties: {})
    worker = described_class.new

    allow(worker).to receive(:resolve_target_folder).and_return(nil)
    allow_any_instance_of(Asset).to receive(:broadcast_for_embedding)
    allow(described_class).to receive(:perform_async)

    worker.perform(batch.id)

    asset = Asset.order(:created_at).last
    expect(asset.user_id).to eq(fallback_user.id)
  end

  it "passes nil user fallbacks to asset creation when no users exist" do
    batch = create(:ingestion_batch, status: :review_needed, initiated_by_id: nil)
    item = create(:ingestion_item, ingestion_batch: batch, status: :ready_for_import, original_filename: "hero.jpg")
    asset_versions = instance_double(ActiveRecord::Associations::CollectionProxy)
    version = instance_double(AssetVersion, id: SecureRandom.uuid)
    asset = instance_double(Asset, asset_versions: asset_versions, uuid: SecureRandom.uuid)
    worker = described_class.new

    allow(User).to receive(:first).and_return(nil)
    allow(worker).to receive(:resolve_target_folder).and_return(nil)
    allow(asset_versions).to receive(:create!).and_return(version)
    allow(asset).to receive(:update!)
    allow(asset).to receive(:respond_to?).with(:broadcast_for_embedding, true).and_return(false)
    expect(Asset).to receive(:create!).with(hash_including(user_id: nil)).and_return(asset)

    worker.send(:commit_item!, batch, item)
  end

  it "creates fallback folders with the first user when initiated_by_id is missing" do
    fallback_user = create(:user)
    batch = create(:ingestion_batch, initiated_by_id: nil, source_type: "ftp", created_at: Time.zone.parse("2026-07-01"))

    folder = described_class.new.send(:resolve_target_folder, batch, {})

    expect(folder.user_id).to eq(fallback_user.id)
    expect(folder.name).to include("FTP")
  end

  it "passes nil user_id when resolving a fallback folder without any users" do
    batch = create(:ingestion_batch, initiated_by_id: nil, source_type: "ftp", created_at: Time.zone.parse("2026-07-01"))
    allow(User).to receive(:first).and_return(nil)

    expect(Folder).to receive(:find_or_create_by!).with(hash_including(user_id: nil)).and_call_original

    described_class.new.send(:resolve_target_folder, batch, {})
  end
end
