require 'rails_helper'

RSpec.describe 'Api::V1::MetadataExports', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /api/v1/metadata_exports' do
    it 'returns the current user\'s non-expired exports' do
      mine    = create(:metadata_export, :completed, user: user, name: 'mine')
      expired = create(:metadata_export, :expired, user: user)
      other   = create(:metadata_export, :completed, user: create(:user))

      get '/api/v1/metadata_exports'

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body).map { |e| e['id'] }
      expect(ids).to include(mine.id)
      expect(ids).not_to include(expired.id, other.id)
    end
  end

  describe 'POST /api/v1/metadata_exports' do
    it 'creates an export and enqueues the worker' do
      folder = create(:folder, user: user)

      expect {
        post '/api/v1/metadata_exports', params: {
          metadata_export: {
            name: 'q3_assets', folder_id: folder.id,
            include_subfolders: true, property_mode: 'all'
          },
        }, as: :json
      }.to change(MetadataExportWorker.jobs, :size).by(1)

      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body['name']).to eq('q3_assets')
      expect(body['status']).to eq('pending')
    end
  end

  describe 'GET /api/v1/metadata_exports/properties' do
    it 'returns the union of property keys for the folder' do
      folder = create(:folder, user: user)
      create(:asset, folder: folder, user: user, properties: { 'copyright' => 'A', 'region' => 'EMEA' })

      get '/api/v1/metadata_exports/properties', params: { folder_id: folder.id }

      expect(response).to have_http_status(:ok)
      props = JSON.parse(response.body)['properties']
      expect(props).to include('copyright', 'region')
    end
  end

  describe 'GET /api/v1/metadata_exports/:id/download' do
    it 'returns 404 when the export is not yet completed' do
      export = create(:metadata_export, user: user)
      get "/api/v1/metadata_exports/#{export.id}/download"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/metadata_exports/:id' do
    it 'destroys the export' do
      export = create(:metadata_export, user: user)
      delete "/api/v1/metadata_exports/#{export.id}"
      expect(response).to have_http_status(:ok)
      expect(MetadataExport.find_by(id: export.id)).to be_nil
    end
  end
end

# ---- merged from metadata_exports_coverage_spec.rb ----
RSpec.describe "Api::V1::MetadataExports coverage", type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
    allow(MetadataExportWorker).to receive(:perform_async)
    allow(MetadataExportWorker).to receive(:perform_at)
  end

  def json = response.parsed_body

  def attach_export_file(export, filename: "export.csv")
    File.open(Rails.root.join("spec/fixtures/files/metadata_import_sample.csv")) do |file|
      export.files.attach(io: file, filename: filename, content_type: "text/csv")
    end
  end

  it "serializes a single export including folder name and attached files" do
    folder = create(:folder, user: user, name: "Exports")
    export = create(:metadata_export, :completed, :selective, user: user, folder: folder, name: "Selective")
    attach_export_file(export)

    get "/api/v1/metadata_exports/#{export.id}", as: :json

    expect(response).to have_http_status(:ok)
    expect(json).to include(
      "id" => export.id,
      "folder_name" => "Exports",
      "property_mode" => "selective",
      "selected_properties" => %w[description copyright]
    )
    expect(json["files"].first).to include("filename" => "export.csv")
    expect(json["files"].first["download_url"]).to include("/api/v1/metadata_exports/#{export.id}/download")
  end

  it "collects root and cascading child property keys" do
    parent = create(:folder, user: user)
    child = create(:folder, user: user, parent: parent)
    create(:asset, user: user, properties: { "root_only" => true })
    create(:asset, user: user, folder: parent, properties: { "parent_key" => true })
    create(:asset, user: user, folder: child, properties: { "child_key" => true })

    get "/api/v1/metadata_exports/properties", params: { folder_id: "root", include_subfolders: false }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json["properties"]).to include("root_only")
    expect(json["properties"]).not_to include("parent_key")

    get "/api/v1/metadata_exports/properties", params: { folder_id: parent.id, include_subfolders: true }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json["properties"]).to include("parent_key", "child_key")
  end

  it "creates root scheduled exports and reports validation errors" do
    scheduled_at = 1.day.from_now

    post "/api/v1/metadata_exports", params: {
      metadata_export: {
        name: "Scheduled",
        folder_id: "root",
        property_mode: "all",
        scheduled_at: scheduled_at.iso8601,
      },
    }, as: :json

    expect(response).to have_http_status(:accepted)
    expect(MetadataExportWorker).to have_received(:perform_at).with(kind_of(Time), json["id"])
    expect(MetadataExport.find(json["id"]).folder_id).to be_nil

    post "/api/v1/metadata_exports", params: {
      metadata_export: { name: "", property_mode: "unknown" },
    }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["errors"]).to be_present
  end

  it "downloads ready files and handles missing attachment selections" do
    export = create(:metadata_export, :completed, user: user)
    attach_export_file(export, filename: "ready.csv")

    get "/api/v1/metadata_exports/#{export.id}/download", as: :json
    expect(response).to have_http_status(:redirect)
    expect(response.location).to include("/rails/active_storage/blobs/redirect/")

    get "/api/v1/metadata_exports/#{export.id}/download", params: { attachment_id: "0" }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(json).to eq("error" => "File not found.")
  end

  it "purges attached files when destroyed" do
    export = create(:metadata_export, :completed, user: user)
    attach_export_file(export)

    delete "/api/v1/metadata_exports/#{export.id}", as: :json

    expect(response).to have_http_status(:ok)
    expect(MetadataExport.exists?(export.id)).to be(false)
    expect(json).to eq("success" => true)
  end
end
