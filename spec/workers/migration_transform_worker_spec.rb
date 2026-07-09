require "rails_helper"

RSpec.describe MigrationTransformWorker, type: :worker do
  let(:batch) { create(:ingestion_batch, status: :transforming, total_count: 1) }

  it "returns early when the item is missing or already terminal" do
    committed = create(:ingestion_item, ingestion_batch: batch, status: :committed)
    rejected = create(:ingestion_item, ingestion_batch: batch, status: :rejected)

    expect { described_class.new.perform(0) }.not_to raise_error
    expect { described_class.new.perform(committed.id) }.not_to change { committed.reload.status }
    expect { described_class.new.perform(rejected.id) }.not_to change { rejected.reload.status }
  end

  it "returns early when the item has no batch" do
    item = build_stubbed(:ingestion_item, ingestion_batch: nil, status: :pending)
    allow(IngestionItem).to receive(:find_by).with(id: item.id).and_return(item)

    expect { described_class.new.perform(item.id) }.not_to raise_error
  end

  it "rejects flagged duplicates and updates batch progress" do
    item = create(:ingestion_item, ingestion_batch: batch, status: :flagged_duplicate)

    described_class.new.perform(item.id)

    expect(item.reload).to be_rejected
    expect(item.error_log).to include("Deduplication")
    expect(batch.reload).to be_review_needed
  end

  it "normalizes metadata with the rule-based fallback when the gateway is unavailable" do
    item = create(:ingestion_item, ingestion_batch: batch, legacy_metadata: { "dc:title" => "Hero", "keywords" => "summer" })
    allow_any_instance_of(described_class).to receive(:call_ai_gateway).and_return(nil)

    described_class.new.perform(item.id)

    expect(item.reload).to be_ready_for_import
    expect(item.clean_properties).to include("title" => "Hero", "tags" => [ "summer" ])
  end

  it "uses normalized metadata returned by the AI gateway" do
    item = create(:ingestion_item, ingestion_batch: batch, original_filename: "hero.jpg")

    stub_request(:post, "http://localhost:8000/api/tdm/normalize")
      .with(body: { filename: "hero.jpg", metadata: {} }.to_json)
      .to_return(status: 200, body: { title: "Gateway Hero", tags: [ "approved" ] }.to_json)

    described_class.new.perform(item.id)

    expect(item.reload.clean_properties).to include("title" => "Gateway Hero", "tags" => [ "approved" ])
  end

  it "falls back to canonicalized metadata and the literal filename (with extension) as title when the gateway returns an error" do
    item = create(
      :ingestion_item,
      ingestion_batch: batch,
      original_filename: "launch-video.mov",
      legacy_metadata: {
        "caption" => "Launch",
        "cq:tags" => [ "hero", "hero" ],
        "custom field" => "custom",
      }
    )

    stub_request(:post, "http://localhost:8000/api/tdm/normalize")
      .to_return(status: 500, body: "{}")

    described_class.new.perform(item.id)

    expect(item.reload.clean_properties).to include(
      "title" => "launch-video.mov",
      "description" => "Launch",
      "tags" => [ "hero" ],
      "custom_field" => "custom"
    )
  end

  it "does not transition an incomplete batch" do
    incomplete_batch = create(:ingestion_batch, status: :transforming, total_count: 2)
    item = create(:ingestion_item, ingestion_batch: incomplete_batch)
    create(:ingestion_item, ingestion_batch: incomplete_batch, status: :pending)
    allow_any_instance_of(described_class).to receive(:call_ai_gateway).and_return(nil)

    described_class.new.perform(item.id)

    expect(incomplete_batch.reload).to be_transforming
  end

  it "does not transition batches outside extraction or transformation" do
    initializing_batch = create(:ingestion_batch, status: :initializing, total_count: 1)
    item = create(:ingestion_item, ingestion_batch: initializing_batch)
    allow_any_instance_of(described_class).to receive(:call_ai_gateway).and_return(nil)

    described_class.new.perform(item.id)

    expect(initializing_batch.reload).to be_initializing
  end

  it "flags the item, increments errors and reraises on failures" do
    item = create(:ingestion_item, ingestion_batch: batch)
    allow_any_instance_of(described_class).to receive(:normalize_metadata).and_raise(StandardError, "boom")

    expect { described_class.new.perform(item.id) }.to raise_error(StandardError, "boom")
    expect(item.reload).to be_flagged_error
    expect(batch.reload.error_count).to eq(1)
  end
end
