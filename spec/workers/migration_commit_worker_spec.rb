require "rails_helper"

RSpec.describe MigrationCommitWorker, type: :worker do
  let(:user) { create(:user) }
  let(:batch) { create(:ingestion_batch, status: :review_needed, initiated_by_id: user.id, total_count: 1) }
  let(:adapter) { instance_double("IngestionAdapter", download_and_stream: "/tmp/staged-file.jpg") }

  before do
    allow(IngestionAdapters::Factory).to receive(:build).and_return(adapter)
    allow(AssetProcessorWorker).to receive(:perform_async)
  end

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
    expect(described_class).to have_received(:perform_async).with(batch.id)
    expect(AssetProcessorWorker).to have_received(:perform_async).with(asset.active_version_id, "/tmp/staged-file.jpg")
  end

  it "falls back to the literal filename (with extension, not titleized) when clean_properties has no title" do
    create(
      :ingestion_item,
      ingestion_batch: batch,
      status: :ready_for_import,
      original_filename: "/content/dam/US/marketing-assets/715839_C_CascadeMilling_OrganicPancakeMix_S.psd",
      clean_properties: { "description" => "Desc" }
    )
    allow(described_class).to receive(:perform_async)
    allow_any_instance_of(Asset).to receive(:broadcast_for_embedding)

    described_class.new.perform(batch.id)

    asset = Asset.order(:created_at).last
    expect(asset.title).to eq("715839_C_CascadeMilling_OrganicPancakeMix_S.psd")
  end

  it "commits the full per-asset metadata directly onto the version's properties" do
    create(:ingestion_item, ingestion_batch: batch, status: :ready_for_import,
      clean_properties: { "title" => "Hero" },
      full_metadata: { "dc:title" => "Hero", "dc:description" => "Full desc", "cq:tags" => [ "a" ] })
    allow(described_class).to receive(:perform_async)
    allow_any_instance_of(Asset).to receive(:broadcast_for_embedding)

    described_class.new.perform(batch.id)

    version = Asset.order(:created_at).last.asset_versions.first
    expect(version.properties["full_metadata"]).to eq(
      "dc:title" => "Hero", "dc:description" => "Full desc", "cq:tags" => [ "a" ]
    )
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
    expect(AssetProcessorWorker).not_to have_received(:perform_async)
  end

  it "regression: re-downloads the source binary and hands it to AssetProcessorWorker " \
     "instead of leaving committed assets as metadata-only records stuck at status: pending" do
    item = create(:ingestion_item, ingestion_batch: batch, status: :ready_for_import,
                                    original_filename: "/content/dam/hero.jpg")
    allow(described_class).to receive(:perform_async)
    allow_any_instance_of(Asset).to receive(:broadcast_for_embedding)

    described_class.new.perform(batch.id)

    expect(adapter).to have_received(:download_and_stream).with("/content/dam/hero.jpg")
    asset = Asset.order(:created_at).last
    expect(AssetProcessorWorker).to have_received(:perform_async).with(asset.active_version_id, "/tmp/staged-file.jpg")
  end

  it "regression: does not enqueue AssetProcessorWorker and cleans up the staged " \
     "tempfile when the download succeeds but the commit transaction fails afterwards" do
    staged_path = Tempfile.new("regression-cleanup").tap { |f| f.write("data"); f.rewind }.path
    allow(adapter).to receive(:download_and_stream).and_return(staged_path)
    item = create(:ingestion_item, ingestion_batch: batch, status: :ready_for_import)
    allow(Asset).to receive(:create!).and_raise(StandardError, "invalid asset")

    described_class.new.send(:commit_item!, batch, item)

    expect(AssetProcessorWorker).not_to have_received(:perform_async)
    expect(File.exist?(staged_path)).to be false
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
