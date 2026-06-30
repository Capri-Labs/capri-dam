# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ingestion pipeline", type: :integration, aggregate_failures: true do
  let(:admin_user) { create(:user, :admin) }
  let(:json_headers) do
    {
      "ACCEPT" => "application/json",
      "CONTENT_TYPE" => "application/json",
    }
  end
  let(:runtime_file) { Rails.root.join("spec/fixtures/files/integration-ingestion-copy.jpg") }

  before do
    sign_in admin_user
    redis_client = double("RedisClient", publish: true)
    Redis.singleton_class.send(:define_method, :current) { redis_client } unless Redis.respond_to?(:current)
    allow(Redis).to receive(:new).and_return(redis_client)
  end

  after do
    File.delete(runtime_file) if File.exist?(runtime_file)
  end

  it "creates a connector, runs extraction, lists items, and aborts the batch" do
    fixture_path = Rails.root.join("spec/fixtures/images/test-image.jpg")
    adapter = instance_double("IngestionAdapter")
    allow(adapter).to receive(:fetch_next_chunk).with(nil).and_return(
      {
        files: [
          { identifier: "test-image.jpg", size: File.size(fixture_path) },
        ],
        next_cursor: nil,
        has_more: false,
      }
    )
    allow(adapter).to receive(:download_and_stream) do |_identifier, &block|
      File.open(fixture_path, "rb") do |file|
        while (chunk = file.read(1024))
          block.call(chunk)
        end
      end
      File.binwrite(runtime_file, File.binread(fixture_path))
      runtime_file.to_s
    end
    stub_const("Ingestion", Module.new) unless defined?(Ingestion)
    stub_const("Ingestion::Factory", Class.new do
      def self.build(*); end
    end)
    allow(Ingestion::Factory).to receive(:build).and_return(adapter)

    post "/api/v1/system_connectors",
         params: {
           system_connector: {
             name: "Integration Connector",
             provider_type: "aem",
             endpoint: "https://connector.example.test",
             auth_token: "secret-token",
           },
         }.to_json,
         headers: json_headers
    expect(response).to have_http_status(:created)
    connector_id = json_body.fetch("id")

    patch "/api/v1/system_connectors/#{connector_id}",
          params: { system_connector: { status: "active" } }.to_json,
          headers: json_headers
    expect(response).to have_http_status(:ok)

    post "/api/v1/system_connectors/#{connector_id}/start_migration", headers: { "ACCEPT" => "application/json" }
    expect(response).to have_http_status(:accepted), response.body
    batch_id = json_body.fetch("batch").fetch("id")
    expect(json_body.fetch("batch").fetch("status")).to eq("initializing")

    batch = IngestionBatch.find(batch_id)
    expect(batch.status).to be_in(%w[extracting transforming])

    PreFlightAnalysisWorker.new.perform(connector_id)
    expect(SystemConnector.find(connector_id).analysis_report).to be_present

    item = batch.reload.ingestion_items.first
    patch "/api/v1/ingestion_items/#{item.id}",
          params: {
            ingestion_item: {
              status: "ready_for_import",
              clean_properties: { title: "Clean Title" },
            },
          }.to_json,
          headers: json_headers
    expect(response).to have_http_status(:ok)
    expect(batch.reload.status).to eq("review_needed")

    get "/api/v1/ingestion_items", params: { batch_id: batch.id }
    expect(response).to have_http_status(:ok)
    expect(json_body.fetch("items").map { |entry| entry.fetch("id") }).to include(item.id)

    post "/api/v1/ingestion_batches/#{batch.id}/abort", headers: { "ACCEPT" => "application/json" }
    expect(response).to have_http_status(:ok)
    expect(batch.reload.status).to eq("failed")
  end
end
