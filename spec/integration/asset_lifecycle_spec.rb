# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Asset lifecycle", type: :integration, aggregate_failures: true do
  let(:admin_user) { create(:user, :admin) }
  let(:runtime_upload_path) { Rails.root.join("spec/fixtures/files/runtime-asset-upload.jpg") }
  let(:json_headers) do
    {
      "ACCEPT" => "application/json",
      "CONTENT_TYPE" => "application/json",
    }
  end
  let(:upload_file) do
    Rack::Test::UploadedFile.new(runtime_upload_path, "image/jpeg", true)
  end

  before do
    File.binwrite(runtime_upload_path, File.binread(Rails.root.join("spec/fixtures/images/test-image.jpg")))
    create(:storage_backend, active: true) unless StorageBackend.where(active: true).exists?
    sign_in admin_user

    allow(AssetProcessorWorker).to receive(:perform_async) do |version_id, staging_path|
      AssetProcessorWorker.new.perform(version_id, staging_path)
    end
    allow(CdnInvalidationWorker).to receive(:perform_async) if defined?(CdnInvalidationWorker)
    allow(EdgeMetadataSyncWorker).to receive(:perform_async) if defined?(EdgeMetadataSyncWorker)
    allow(AssetWorkflowTriggerWorker).to receive(:perform_async) if defined?(AssetWorkflowTriggerWorker)
    allow(DuplicateDetectionWorker).to receive(:perform_async) if defined?(DuplicateDetectionWorker)
    allow_any_instance_of(AssetProcessorWorker).to receive(:extract_image_metadata) do |_worker, _path, meta|
      meta[:width] = 1
      meta[:height] = 1
      meta[:aspect_ratio] = 1.0
      meta[:resolution] = "1 x 1"
      meta[:color_space] = "sRGB"
      meta[:color_palette] = []
    end
    allow_any_instance_of(AssetProcessorWorker).to receive(:extract_text_from_image)
  end

  after do
    File.delete(runtime_upload_path) if File.exist?(runtime_upload_path)
  end

  it "covers upload, search, versioning, recycle bin, and restore" do
    post "/api/v1/folders",
         params: { folder: { name: "Integration Folder", parent_id: "root" } }.to_json,
         headers: json_headers
    expect(response).to have_http_status(:created)
    folder_id = json_body.fetch("id")

    post "/api/v1/assets",
         params: {
           title: "Integration Asset",
           folder_id: folder_id,
           file: upload_file,
         }
    expect(response).to have_http_status(:accepted)
    asset_id = json_body.fetch("id")

    get "/api/v1/assets/#{asset_id}"
    expect(response).to have_http_status(:ok)
    expect(json_body.fetch("uuid")).to eq(asset_id)

    drain_sidekiq

    get "/api/v1/assets/#{asset_id}"
    expect(json_body.fetch("status")).to eq("ready")

    get "/api/v1/search", params: { q: "Integration Asset", mode: "images" }
    expect(response).to have_http_status(:ok)
    expect(json_body.fetch("results").map { |result| result.fetch("uuid") }).to include(asset_id)

    patch "/api/v1/assets/#{asset_id}",
          params: { asset: { title: "Integration Asset Updated", tags: %w[integration updated] } }.to_json,
          headers: json_headers
    expect(response).to have_http_status(:ok)
    expect(json_body.fetch("title")).to eq("Integration Asset Updated")
    expect(json_body.dig("metadata", "tags")).to eq(%w[integration updated])

    get "/api/v1/assets/#{asset_id}/versions"
    expect(response).to have_http_status(:ok)
    expect(json_body.fetch("versions")).not_to be_empty

    delete "/api/v1/assets/#{asset_id}"
    expect(response).to have_http_status(:ok)

    get "/api/v1/bin"
    expect(response).to have_http_status(:ok)
    expect(json_body.fetch("items").map { |item| item.fetch("id") }).to include(asset_id)

    post "/api/v1/assets/#{asset_id}/restore"
    expect(response).to have_http_status(:ok)

    get "/api/v1/assets/#{asset_id}"
    expect(response).to have_http_status(:ok)
    expect(json_body.fetch("trashed")).to be(false)
  end
end
