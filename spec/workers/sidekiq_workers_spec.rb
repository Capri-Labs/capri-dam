require "rails_helper"
require "sidekiq/testing"

Sidekiq::Testing.fake!

RSpec.describe EmailDispatcherWorker, type: :worker do
  before { described_class.clear }

  let(:template) do
    create(
      :email_template,
      subject: "Hello {{ user.first_name }}",
      html_body: "<p>Hello {{ user.first_name }}</p>",
      text_body: "Hello {{ user.first_name }}",
    )
  end
  let(:delivery) { create(:email_delivery, email_template: template, payload: { "user" => { "first_name" => "Alex" } }) }

  it "queues the job" do
    expect { described_class.perform_async(delivery.id) }.to change(described_class.jobs, :size).by(1)
  end

  it "marks deliveries as sent after a successful dispatch" do
    mail = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    allow(DynamicMailer).to receive(:dispatch_email).and_return(mail)

    described_class.new.perform(delivery.id)

    expect(delivery.reload.status).to eq("sent")
    expect(DynamicMailer).to have_received(:dispatch_email).with(
      to: delivery.recipient_email,
      subject: "Hello Alex",
      html_body: "<p>Hello Alex</p>",
      text_body: "Hello Alex",
    )
  end

  it "increments retry count and reraises mail failures" do
    mail = instance_double(ActionMailer::MessageDelivery)
    allow(DynamicMailer).to receive(:dispatch_email).and_return(mail)
    allow(mail).to receive(:deliver_now).and_raise(StandardError, "SMTP down")

    expect { described_class.new.perform(delivery.id) }.to raise_error(StandardError, "SMTP down")

    expect(delivery.reload.retry_count).to eq(1)
    expect(delivery.error_log).to include("Attempt 1 failed: SMTP down")
  end
end

RSpec.describe FolderMetadataSyncWorker, type: :worker do
  before { described_class.clear }

  it "queues the job" do
    expect { described_class.perform_async("folder-id") }.to change(described_class.jobs, :size).by(1)
  end

  it "enqueues edge metadata sync for assets and child folders" do
    folder = create(:folder)
    asset = instance_double(Asset, uuid: "asset-uuid")
    child = instance_double(Folder, id: "child-folder-id")
    asset_scope = instance_double(ActiveRecord::Relation)
    folder_scope = instance_double(ActiveRecord::Relation)
    asset_selector = instance_double(ActiveRecord::Relation)
    folder_selector = instance_double(ActiveRecord::Relation)

    allow(Asset).to receive(:active).and_return(asset_scope)
    allow(asset_scope).to receive(:where).with(folder_id: folder.id).and_return(asset_selector)
    allow(asset_selector).to receive(:select).with(:uuid).and_return(asset_selector)
    allow(asset_selector).to receive(:find_each).and_yield(asset)
    allow(Folder).to receive(:active).and_return(folder_scope)
    allow(folder_scope).to receive(:find_by).with(id: folder.id).and_return(folder)
    allow(folder_scope).to receive(:where).with(parent_id: folder.id).and_return(folder_selector)
    allow(folder_selector).to receive(:select).with(:id).and_return(folder_selector)
    allow(folder_selector).to receive(:find_each).and_yield(child)
    allow(EdgeMetadataSyncWorker).to receive(:perform_async)
    allow(described_class).to receive(:perform_async)

    described_class.new.perform(folder.id)

    expect(EdgeMetadataSyncWorker).to have_received(:perform_async).with(asset.uuid)
    expect(described_class).to have_received(:perform_async).with(child.id)
  end

  it "returns without enqueuing when the folder cannot be found" do
    allow(Folder).to receive_message_chain(:active, :find_by).and_return(nil)
    allow(EdgeMetadataSyncWorker).to receive(:perform_async)
    allow(described_class).to receive(:perform_async)

    described_class.new.perform('missing-folder-id')

    expect(EdgeMetadataSyncWorker).not_to have_received(:perform_async)
    expect(described_class).not_to have_received(:perform_async)
  end
end

RSpec.describe IngestionWorker, type: :worker do
  before { described_class.clear }

  let(:payload_json) { { asset: { name: "hero.jpg", properties: { "copyright" => "ACME" } } }.to_json }

  it "queues the job" do
    expect { described_class.perform_async(1, payload_json) }.to change(described_class.jobs, :size).by(1)
  end

  it "requeues rate-limited jobs" do
    connector = create(:system_connector, status: "active")
    worker = described_class.new
    allow(worker).to receive(:rate_limited?).and_return(true)
    allow(described_class).to receive(:perform_in)

    worker.perform(connector.id, payload_json)

    expect(described_class).to have_received(:perform_in).with(5.seconds, connector.id, payload_json)
  end

  it "ingests clean assets when sanitation is disabled" do
    connector = create(:system_connector, status: "active", tdm_sanitation: false)
    worker = described_class.new
    allow(worker).to receive(:rate_limited?).and_return(false)
    allow(worker).to receive(:ingest_clean_asset!)

    worker.perform(connector.id, payload_json)

    expect(worker).to have_received(:ingest_clean_asset!).with(
      connector,
      "hero.jpg",
      { "copyright" => "ACME" },
      hash_including("asset" => hash_including("name" => "hero.jpg")),
    )
  end

  it "quarantines rejected assets when sanitation fails" do
    connector = create(:system_connector, status: "active", tdm_sanitation: true)
    worker = described_class.new
    allow(worker).to receive(:rate_limited?).and_return(false)
    allow(worker).to receive(:evaluate_via_ai_gateway).and_return({ "approved" => false, "reason" => "policy" })
    allow(worker).to receive(:quarantine_dirty_asset!)

    worker.perform(connector.id, payload_json)

    expect(worker).to have_received(:quarantine_dirty_asset!).with(
      connector,
      hash_including("asset" => hash_including("name" => "hero.jpg")),
      "policy",
    )
  end
end

RSpec.describe TrashCleanupWorker, type: :worker do
  before { described_class.clear }

  it "queues the job" do
    expect { described_class.perform_async }.to change(described_class.jobs, :size).by(1)
  end

  it "delegates to BinPurgeWorker" do
    purge_worker = instance_double(BinPurgeWorker, perform: true)
    allow(BinPurgeWorker).to receive(:new).and_return(purge_worker)

    described_class.new.perform

    expect(BinPurgeWorker).to have_received(:new)
    expect(purge_worker).to have_received(:perform)
  end
end

RSpec.describe DataHealthRemediationWorker, type: :worker do
  before { described_class.clear }

  it "queues the job" do
    expect { described_class.perform_async("duplicates", 1) }.to change(described_class.jobs, :size).by(1)
  end

  it "enqueues a duplicate repository scan" do
    allow(Setting).to receive(:get).with("duplicate_manager_scan_status").and_return("idle")
    allow(Setting).to receive(:set)
    allow(DuplicateRepositoryScanWorker).to receive(:perform_async)

    described_class.new.perform("duplicates", 1)

    expect(Setting).to have_received(:set).with("duplicate_manager_scan_status", "queued")
    expect(DuplicateRepositoryScanWorker).to have_received(:perform_async)
  end

  it "queues pre-flight analysis for active connectors" do
    connectors = create_list(:system_connector, 2, status: "active")
    allow(PreFlightAnalysisWorker).to receive(:perform_async)

    described_class.new.perform("missing_metadata", 1)

    connectors.each do |connector|
      expect(PreFlightAnalysisWorker).to have_received(:perform_async).with(connector.id)
    end
  end

  it "flags assets missing copyright metadata" do
    flagged_asset = create(:asset, properties: {})
    safe_asset = create(:asset, properties: { "copyright" => "ACME" })

    described_class.new.perform("copyright", 1)

    expect(flagged_asset.reload.properties["tdm_copyright_flagged"]).to be(true)
    expect(safe_asset.reload.properties["tdm_copyright_flagged"]).to be_nil
  end

  it "handles stale remediation without raising" do
    relation = instance_double(ActiveRecord::Relation, count: 3)
    allow(Asset).to receive(:where).and_return(relation)

    expect { described_class.new.perform("stale", 1) }.not_to raise_error
  end
end

RSpec.describe MetadataExportCleanupWorker, type: :worker do
  before { described_class.clear }

  it "queues the job" do
    expect { described_class.perform_async }.to change(described_class.jobs, :size).by(1)
  end

  it "purges expired exports" do
    export = create(:metadata_export, :expired)
    export.files.attach(io: StringIO.new("id,title\n1,Test"), filename: "export.csv", content_type: "text/csv")

    described_class.new.perform

    expect { export.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end
end

RSpec.describe MetadataImportCleanupWorker, type: :worker do
  before { described_class.clear }

  it "queues the job" do
    expect { described_class.perform_async }.to change(described_class.jobs, :size).by(1)
  end

  it "purges expired imports" do
    import = create(:metadata_import, :expired)
    import.source_file.attach(io: StringIO.new("asset_path,title"), filename: "import.csv", content_type: "text/csv")
    import.result_file.attach(io: StringIO.new("asset_path,title"), filename: "results.csv", content_type: "text/csv")

    described_class.new.perform

    expect { import.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end
end

RSpec.describe MigrationCommitWorker, type: :worker do
  before { described_class.clear }

  it "queues the job" do
    expect { described_class.perform_async("batch-id", 0) }.to change(described_class.jobs, :size).by(1)
  end

  it "finalizes empty batches and enqueues the report worker" do
    batch = create(:ingestion_batch, status: :review_needed)
    allow(MigrationReportWorker).to receive(:perform_async)

    described_class.new.perform(batch.id)

    expect(batch.reload.status).to eq("committed")
    expect(batch.completed_at).to be_present
    expect(MigrationReportWorker).to have_received(:perform_async).with(batch.id)
  end

  it "commits staged items" do
    batch = create(:ingestion_batch, status: :review_needed, initiated_by_id: create(:user).id, source_type: "aem")
    item = create(:ingestion_item, ingestion_batch: batch, status: :ready_for_import, original_filename: "hero.jpg")
    asset_versions = instance_double(ActiveRecord::Associations::CollectionProxy)
    version = instance_double(AssetVersion, id: SecureRandom.uuid)
    asset = instance_double(Asset, asset_versions: asset_versions, uuid: SecureRandom.uuid)
    worker = described_class.new

    allow(worker).to receive(:resolve_target_folder).and_return(nil)
    allow(Asset).to receive(:create!).and_return(asset)
    allow(asset_versions).to receive(:create!).and_return(version)
    allow(asset).to receive(:update!)
    allow(asset).to receive(:respond_to?).with(:broadcast_for_embedding, true).and_return(false)

    worker.send(:commit_item!, batch, item)

    expect(Asset).to have_received(:create!).with(hash_including(title: "Hero", properties: hash_including(:original_filename)))
    expect(asset_versions).to have_received(:create!)
    expect(item.reload.status).to eq("committed")
  end
end

RSpec.describe MigrationReportWorker, type: :worker do
  before { described_class.clear }

  it "queues the job" do
    expect { described_class.perform_async("batch-id") }.to change(described_class.jobs, :size).by(1)
  end

  it "updates the batch with the generated snapshot" do
    batch = create(:ingestion_batch)
    snapshot = instance_double(ReportSnapshot, id: 123)
    worker = described_class.new
    allow(worker).to receive(:compute_stats).and_return(batch_id: batch.id, batch_name: batch.name)
    allow(worker).to receive(:persist_report_snapshot).and_return(snapshot)
    allow(worker).to receive(:notify_batch_complete)

    worker.perform(batch.id)

    expect(batch.reload.report_snapshot_id).to eq(123)
    expect(worker).to have_received(:notify_batch_complete).with(batch, hash_including(:batch_id, :batch_name), snapshot)
  end
end

RSpec.describe MigrationTransformWorker, type: :worker do
  before { described_class.clear }

  it "queues the job" do
    expect { described_class.perform_async("item-id") }.to change(described_class.jobs, :size).by(1)
  end

  it "marks duplicate items as rejected" do
    batch = create(:ingestion_batch, status: :transforming, total_count: 1)
    item = create(:ingestion_item, ingestion_batch: batch, status: :flagged_duplicate)

    described_class.new.perform(item.id)

    expect(item.reload.status).to eq("rejected")
    expect(item.error_log).to include("Deduplication: exact hash match found in live DAM.")
  end

  it "stores normalized metadata for clean items" do
    batch = create(:ingestion_batch, status: :transforming, total_count: 1)
    item = create(:ingestion_item, ingestion_batch: batch, status: :pending, original_filename: "hero.jpg")
    worker = described_class.new
    allow(worker).to receive(:normalize_metadata).and_return({ "title" => "Hero", "tags" => [ "promo" ] })

    worker.perform(item.id)

    expect(item.reload.status).to eq("ready_for_import")
    expect(item.clean_properties["title"]).to eq("Hero")
  end

  it "falls back to canonical field mapping" do
    normalized = described_class.new.send(
      :fallback_normalize,
      "hero-shot.jpg",
      { "dc:title" => "Hero Shot", "keywords" => [ "summer", "launch" ] },
    )

    expect(normalized).to include("title" => "Hero Shot", "tags" => [ "summer", "launch" ])
  end
end
