require "rails_helper"

RSpec.describe IngestionWorker, type: :worker do
  let(:connector) { create(:system_connector, status: "active", rps_limit: 5) }
  let(:payload) { { asset: { name: "hero.jpg", properties: { "description" => "summer" } } }.to_json }
  let(:redis) do
    Class.new do
      attr_accessor :count
      def initialize(count) = @count = count
      def get(_key) = count
      def multi
        yield self
      end
      def incr(_key) = self.count += 1
      def expire(_key, _ttl) = true
    end.new(0)
  end

  before do
    allow(Sidekiq).to receive(:redis).and_yield(redis)
    allow(SmartCollectionRouterWorker).to receive(:perform_async)
  end

  it "returns early when the connector is missing or inactive" do
    inactive = create(:system_connector, status: "inactive")

    expect { described_class.new.perform(0, payload) }.not_to change(Asset, :count)
    expect { described_class.new.perform(inactive.id, payload) }.not_to change(Asset, :count)
  end

  it "reschedules and returns when the connector is rate limited" do
    redis.count = 5
    allow(described_class).to receive(:perform_in)

    described_class.new.perform(connector.id, payload)

    expect(described_class).to have_received(:perform_in).with(5.seconds, connector.id, payload)
    expect(Asset.count).to eq(0)
  end

  it "delegates non-TDM payloads to clean ingestion" do
    worker = described_class.new
    allow(worker).to receive(:ingest_clean_asset!)

    worker.perform(connector.id, payload)

    expect(worker).to have_received(:ingest_clean_asset!).with(connector, "hero.jpg", { "description" => "summer" }, JSON.parse(payload))
  end

  it "uses fallback filename and metadata when payload fields are missing" do
    worker = described_class.new
    allow(worker).to receive(:ingest_clean_asset!)
    allow(Time).to receive(:now).and_return(Time.zone.local(2026, 7, 2, 10, 23, 37))

    worker.perform(connector.id, { asset: {} }.to_json)

    expect(worker).to have_received(:ingest_clean_asset!).with(
      connector,
      "unknown_file_1782987817",
      {},
      { "asset" => {} }
    )
  end

  it "ingests approved TDM payloads after a successful gateway evaluation" do
    connector.update!(tdm_sanitation: true)
    worker = described_class.new
    allow(worker).to receive(:ingest_clean_asset!)

    stub_request(:post, "http://localhost:8000/api/tdm/evaluate")
      .with(body: { filename: "hero.jpg", metadata: { "description" => "summer" } }.to_json)
      .to_return(status: 200, body: { approved: true }.to_json)

    worker.perform(connector.id, payload)

    expect(worker).to have_received(:ingest_clean_asset!).with(connector, "hero.jpg", { "description" => "summer" }, JSON.parse(payload))
  end

  it "quarantines rejected TDM payloads" do
    connector.update!(tdm_sanitation: true)
    worker = described_class.new
    allow(worker).to receive(:evaluate_via_ai_gateway).and_return("approved" => false, "reason" => "blocked")

    expect { worker.perform(connector.id, payload) }.to change(QuarantinedAsset, :count).by(1)
    expect(QuarantinedAsset.last.rejection_reason).to eq("blocked")
  end

  it "falls back to a rejected TDM response when the AI gateway fails" do
    stub_request(:post, "http://localhost:8000/api/tdm/evaluate").to_raise(Errno::ECONNREFUSED)

    result = described_class.new.send(:evaluate_via_ai_gateway, "hero.jpg", {})

    expect(result).to include("approved" => false, "reason" => "AI Gateway Timeout/Error")
  end

  it "falls back to a rejected TDM response when the AI gateway returns an error" do
    stub_request(:post, "http://localhost:8000/api/tdm/evaluate")
      .to_return(status: 503, body: "unavailable")

    result = described_class.new.send(:evaluate_via_ai_gateway, "hero.jpg", {})

    expect(result).to include("approved" => false, "reason" => "AI Gateway Timeout/Error")
  end

  it "returns vectors from the embedding gateway and nil for failed responses" do
    stub_request(:post, "http://localhost:8000/api/embed_query")
      .with(body: { text: "hello" }.to_json)
      .to_return(status: 200, body: { vector: [ 0.1, 0.2 ] }.to_json)
    expect(described_class.new.send(:fetch_vector_embedding, "hello")).to eq([ 0.1, 0.2 ])

    stub_request(:post, "http://localhost:8000/api/embed_query").to_return(status: 500, body: "{}")
    expect(described_class.new.send(:fetch_vector_embedding, "hello")).to be_nil
  end

  it "creates a clean asset, updates connector sync fields and routes embedded assets" do
    create(:user)
    vector = Array.new(1_536, 0.1)
    allow_any_instance_of(described_class).to receive(:fetch_vector_embedding).and_return(vector)

    expect {
      described_class.new.send(
        :ingest_clean_asset!,
        connector,
        "hero.jpg",
        { "description" => "summer" },
        JSON.parse(payload)
      )
    }.to change(Asset, :count).by(1)

    asset = Asset.last
    expect(asset).to have_attributes(title: "hero.jpg", properties: { "description" => "summer" })
    expect(asset.asset_embedding.embedding).to eq(vector)
    expect(asset.asset_embedding.model_name).to eq("ingestion-worker")
    expect(connector.reload.assets_imported).to eq(1)
    expect(connector.last_sync).to be_present
    expect(SmartCollectionRouterWorker).to have_received(:perform_async).with(asset.id)
  end

  it "creates a clean asset without routing when vector generation fails" do
    create(:user)
    allow_any_instance_of(described_class).to receive(:fetch_vector_embedding).and_return(nil)

    described_class.new.send(:ingest_clean_asset!, connector, "plain.txt", {}, "asset" => {})

    asset = Asset.last
    expect(asset.title).to eq("plain.txt")
    expect(asset.asset_embedding).to be_nil
    expect(SmartCollectionRouterWorker).not_to have_received(:perform_async)
  end
end
