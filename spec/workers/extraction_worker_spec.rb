# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtractionWorker, type: :worker do
  subject(:worker) { described_class.new }

  describe "#perform" do
    it "returns when the batch is missing or not ingestable" do
      inactive_batch = instance_double(IngestionBatch, extracting?: false, initializing?: false)
      allow(IngestionBatch).to receive(:find_by).with(id: 123).and_return(nil)
      allow(IngestionBatch).to receive(:find_by).with(id: 456).and_return(inactive_batch)
      allow(IngestionAdapters::Factory).to receive(:build)

      worker.perform(123)
      worker.perform(456)

      expect(IngestionAdapters::Factory).not_to have_received(:build)
    end

    it "promotes initializing batches to extracting before processing" do
      batch = instance_double(IngestionBatch, extracting?: false, initializing?: true)
      adapter = instance_double("IngestionAdapter")
      allow(IngestionBatch).to receive(:find_by).with(id: 7).and_return(batch)
      allow(batch).to receive(:update!).with(status: :extracting)
      allow(IngestionAdapters::Factory).to receive(:build).with(batch).and_return(adapter)
      allow(worker).to receive(:process_chunk)

      worker.perform(7)

      expect(batch).to have_received(:update!).with(status: :extracting)
      expect(worker).to have_received(:process_chunk).with(batch, adapter)
    end
  end

  describe "#process_chunk" do
    it "uses the stored cursor, skips staged files, updates the cursor, and re-enqueues when more work remains" do
      batch = double("IngestionBatch", id: 9, last_cursor: "cursor-1")
      items = double("ingestion_items")
      adapter = instance_double("IngestionAdapter")

      allow(batch).to receive(:respond_to?).with(:last_cursor).and_return(true)
      allow(batch).to receive(:ingestion_items).and_return(items)
      allow(batch).to receive(:update!)
      allow(batch).to receive(:calculate_progress!)
      allow(items).to receive(:exists?).with(original_filename: "dup.jpg").and_return(true)
      allow(items).to receive(:exists?).with(original_filename: "new.jpg").and_return(false)
      allow(adapter).to receive(:fetch_next_chunk).with("cursor-1").and_return(
        files: [
          { identifier: "dup.jpg", size: 1 },
          { identifier: "new.jpg", size: 2 },
        ],
        next_cursor: "cursor-2",
        has_more: true,
      )
      allow(worker).to receive(:process_single_file)
      allow(described_class).to receive(:perform_async)

      worker.send(:process_chunk, batch, adapter)

      expect(batch).to have_received(:update!).with(last_cursor: "cursor-2")
      expect(worker).to have_received(:process_single_file).with(batch, adapter, hash_including(identifier: "new.jpg"))
      expect(described_class).to have_received(:perform_async).with(9)
      expect(batch).to have_received(:calculate_progress!)
    end

    it "falls back to a nil cursor and transitions to transforming when pagination is finished" do
      batch = double("IngestionBatch", id: 10)
      adapter = instance_double("IngestionAdapter")

      allow(batch).to receive(:respond_to?).with(:last_cursor).and_return(false)
      allow(batch).to receive(:ingestion_items).and_return(double("ingestion_items"))
      allow(batch).to receive(:calculate_progress!)
      allow(batch).to receive(:update!).with(status: :transforming)
      allow(adapter).to receive(:fetch_next_chunk).with(nil).and_return(files: [], has_more: false)
      allow(described_class).to receive(:perform_async)

      worker.send(:process_chunk, batch, adapter)

      expect(batch).to have_received(:update!).with(status: :transforming)
      expect(described_class).not_to have_received(:perform_async)
    end

    it "persists last_cursor on a real IngestionBatch so a multi-page fetch actually advances " \
       "(regression: last_cursor previously didn't exist as a column, so pagination silently " \
       "never advanced and the same first page was re-fetched forever)" do
      batch = create(:ingestion_batch, status: :extracting)
      adapter = instance_double("IngestionAdapter")

      allow(adapter).to receive(:fetch_next_chunk).with(nil).and_return(
        files: [ { identifier: "page-1-file.jpg", size: 1 } ],
        next_cursor: "100",
        has_more: true,
      )
      allow(worker).to receive(:process_single_file)
      allow(described_class).to receive(:perform_async)

      worker.send(:process_chunk, batch, adapter)

      expect(batch.reload.last_cursor).to eq("100")
      expect(described_class).to have_received(:perform_async).with(batch.id)

      # Simulate the re-enqueued job's next invocation: it must read the
      # *persisted* cursor, not start over from offset 0.
      allow(adapter).to receive(:fetch_next_chunk).with("100").and_return(
        files: [], next_cursor: "100", has_more: false
      )

      worker.send(:process_chunk, batch, adapter)

      expect(adapter).to have_received(:fetch_next_chunk).with("100")
      expect(batch.reload).to be_transforming
    end
  end

  describe "#process_single_file" do
    let(:batch) { create(:ingestion_batch, status: :extracting) }
    let(:adapter) { instance_double("IngestionAdapter") }

    it "flags duplicate hashes without broadcasting, but still enqueues transform to reject it" do
      allow(adapter).to receive(:download_and_stream).with("dup.jpg").and_yield("duplicate-bytes").and_return("missing-file")
      allow(Asset).to receive(:column_names).and_return(%w[id file_hash])
      allow(Asset).to receive(:exists?).and_return(true)
      allow(worker).to receive(:broadcast_to_ai_gateway)
      allow(MigrationTransformWorker).to receive(:perform_async)
      allow(File).to receive(:exist?).with("missing-file").and_return(false)
      allow(File).to receive(:delete)

      worker.send(:process_single_file, batch, adapter, identifier: "dup.jpg", size: 12, metadata: { "dc:title" => "Dup" })

      item = batch.ingestion_items.order(:created_at).last
      expect(item).to be_flagged_duplicate
      expect(item.legacy_metadata).to eq("dc:title" => "Dup")
      expect(worker).not_to have_received(:broadcast_to_ai_gateway)
      expect(MigrationTransformWorker).to have_received(:perform_async).with(item.id)
      expect(File).not_to have_received(:delete)
    end

    it "keeps unique hashes pending, persists metadata, broadcasts + enqueues transform, and deletes the temp file" do
      allow(adapter).to receive(:download_and_stream).with("new.jpg").and_yield("unique-bytes").and_return("downloaded-file")
      allow(Asset).to receive(:column_names).and_return(%w[id file_hash])
      allow(Asset).to receive(:exists?).and_return(false)
      allow(worker).to receive(:broadcast_to_ai_gateway)
      allow(MigrationTransformWorker).to receive(:perform_async)
      allow(File).to receive(:exist?).with("downloaded-file").and_return(true)
      allow(File).to receive(:delete).with("downloaded-file")

      worker.send(:process_single_file, batch, adapter, identifier: "new.jpg", size: 20, metadata: { "dc:title" => "New Asset" })

      item = batch.ingestion_items.order(:created_at).last
      expect(item).to be_pending
      expect(item.legacy_metadata).to eq("dc:title" => "New Asset")
      expect(worker).to have_received(:broadcast_to_ai_gateway).with(item)
      expect(MigrationTransformWorker).to have_received(:perform_async).with(item.id)
      expect(File).to have_received(:delete).with("downloaded-file")
    end

    it "defaults legacy_metadata to an empty hash when the adapter provides no metadata key" do
      allow(adapter).to receive(:download_and_stream).with("no-meta.jpg").and_yield("bytes").and_return("temp-file")
      allow(Asset).to receive(:column_names).and_return(%w[id file_hash])
      allow(Asset).to receive(:exists?).and_return(false)
      allow(worker).to receive(:broadcast_to_ai_gateway)
      allow(MigrationTransformWorker).to receive(:perform_async)
      allow(File).to receive(:exist?).with("temp-file").and_return(true)
      allow(File).to receive(:delete).with("temp-file")

      worker.send(:process_single_file, batch, adapter, identifier: "no-meta.jpg", size: 5)

      item = batch.ingestion_items.order(:created_at).last
      expect(item.legacy_metadata).to eq({})
    end

    it "persists the adapter's raw_metadata payload (when present) onto full_metadata for audit purposes" do
      allow(adapter).to receive(:download_and_stream).with("hero.psd").and_yield("bytes").and_return("temp-file")
      allow(Asset).to receive(:column_names).and_return(%w[id file_hash])
      allow(Asset).to receive(:exists?).and_return(false)
      allow(worker).to receive(:broadcast_to_ai_gateway)
      allow(MigrationTransformWorker).to receive(:perform_async)
      allow(File).to receive(:exist?).with("temp-file").and_return(true)
      allow(File).to receive(:delete).with("temp-file")

      worker.send(
        :process_single_file, batch, adapter,
        identifier: "hero.psd", size: 5,
        metadata: { "title" => "Hero" },
        raw_metadata: { "dc:title" => "Hero", "dc:description" => "Full desc" }
      )

      item = batch.ingestion_items.order(:created_at).last
      expect(item.full_metadata).to eq("dc:title" => "Hero", "dc:description" => "Full desc")
    end

    it "defaults full_metadata to an empty hash when the adapter provides no raw_metadata key (migrate_metadata disabled)" do
      allow(adapter).to receive(:download_and_stream).with("no-raw.jpg").and_yield("bytes").and_return("temp-file")
      allow(Asset).to receive(:column_names).and_return(%w[id file_hash])
      allow(Asset).to receive(:exists?).and_return(false)
      allow(worker).to receive(:broadcast_to_ai_gateway)
      allow(MigrationTransformWorker).to receive(:perform_async)
      allow(File).to receive(:exist?).with("temp-file").and_return(true)
      allow(File).to receive(:delete).with("temp-file")

      worker.send(:process_single_file, batch, adapter, identifier: "no-raw.jpg", size: 5, metadata: { "title" => "X" })

      item = batch.ingestion_items.order(:created_at).last
      expect(item.full_metadata).to eq({})
    end

    it "regression: still enqueues MigrationTransformWorker with the real " \
       "(non-stubbed) broadcast_to_ai_gateway, which mutates item.status to " \
       "ai_processing in place — a naive `item.pending?` check performed " \
       "*after* broadcasting would always read false and silently skip the " \
       "enqueue for every newly extracted item" do
      allow(adapter).to receive(:download_and_stream).with("real-broadcast.jpg").and_yield("bytes").and_return("temp-file")
      allow(Asset).to receive(:column_names).and_return(%w[id file_hash])
      allow(Asset).to receive(:exists?).and_return(false)
      allow(MigrationTransformWorker).to receive(:perform_async)
      allow(File).to receive(:exist?).with("temp-file").and_return(true)
      allow(File).to receive(:delete).with("temp-file")

      redis = instance_double(Redis, publish: true)
      without_partial_double_verification { allow(Redis).to receive(:new).and_return(redis) }

      worker.send(:process_single_file, batch, adapter, identifier: "real-broadcast.jpg", size: 5)

      item = batch.ingestion_items.order(:created_at).last
      expect(item).to be_ai_processing
      expect(MigrationTransformWorker).to have_received(:perform_async).with(item.id)
    end
  end

  describe "#broadcast_to_ai_gateway" do
    it "publishes the item uuid when available and marks the item as processing" do
      item = double("IngestionItem", id: 42, uuid: "item-uuid")
      redis = instance_double(Redis, publish: true)
      allow(item).to receive(:update!).with(status: :ai_processing)
      without_partial_double_verification do
        allow(Redis).to receive(:new).and_return(redis)

        worker.send(:broadcast_to_ai_gateway, item)

        expect(redis).to have_received(:publish) do |channel, payload|
          expect(channel).to eq("ai_gateway_events")
          expect(JSON.parse(payload)).to include(
            "event" => "ingestion.item.staged",
            "item_id" => 42,
            "item_uuid" => "item-uuid",
          )
        end
        expect(item).to have_received(:update!).with(status: :ai_processing)
      end
    end
  end
end
