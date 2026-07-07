# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Assets coverage", type: :request do
  let(:user) { create(:user, :admin) }

  before do
    sign_in user
    allow(AssetProcessorWorker).to receive(:perform_async) if defined?(AssetProcessorWorker)
    allow(CdnInvalidationWorker).to receive(:perform_async) if defined?(CdnInvalidationWorker)
    allow(EdgeMetadataSyncWorker).to receive(:perform_async) if defined?(EdgeMetadataSyncWorker)
    allow(Assets::AiAnalysisJob).to receive(:perform_later) if defined?(Assets::AiAnalysisJob)
  end

  def json
    response.parsed_body
  end

  def asset_with_version(title: "Hero", status: :ready, properties: {})
    asset = create(:asset, user: user, title: title, status: status, properties: {
      "original_filename" => "#{title.parameterize}.jpg",
      "content_type" => "image/jpeg",
      "checksum_sha256" => "hash-#{title.parameterize}",
      "size" => 2048,
      "file_size" => 2048,
    }.merge(properties))
    version = create(:asset_version, asset: asset, version_number: 1, created_by: user, properties: asset.properties)
    asset.update!(active_version: version)
    asset
  end

  def coverage_tmp_path(filename)
    Rails.root.join("tmp", "assets_controller_coverage", filename)
  end

  def write_coverage_tmp_file(filename, contents = "coverage-file")
    path = coverage_tmp_path(filename)
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, contents)
    path.to_s
  end

  def processable_asset(title: "Processable")
    source_path = write_coverage_tmp_file("#{title.parameterize}-source.jpg", "source")
    asset_with_version(title: title, properties: {
      "storage_path" => source_path,
      "content_type" => "image/jpeg",
      "file_size" => File.size(source_path),
    })
  end

  def build_assets_controller(params = {})
    Api::V1::AssetsController.new.tap do |controller|
      controller.set_request!(ActionDispatch::TestRequest.create)
      controller.set_response!(ActionDispatch::TestResponse.new)
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(params))
    end
  end

  after do
    FileUtils.rm_rf(Rails.root.join("tmp/assets_controller_coverage"))
  end

  describe "collection endpoints" do
    it "searches ready assets by query and format through the legacy action" do
      jpeg = asset_with_version(title: "Search Hero", properties: { "format" => "jpg" })
      asset_with_version(title: "Search Hero Alt", properties: { "format" => "png" })
      asset_with_version(title: "Ignored Pending", status: :pending, properties: { "format" => "jpg" })
      controller = build_assets_controller(q: "Search Hero", format: "jpg")

      controller.search
      payload = JSON.parse(controller.response.body)

      expect(controller.response).to have_http_status(:ok)
      expect(payload["total"]).to eq(1)
      expect(payload["results"].map { |asset| asset["uuid"] }).to eq([ jpeg.uuid ])
    end

    it "returns every ready asset when no optional search filters are supplied" do
      first = asset_with_version(title: "First Ready")
      second = asset_with_version(title: "Second Ready")
      asset_with_version(title: "Pending", status: :pending)
      controller = build_assets_controller

      controller.search
      payload = JSON.parse(controller.response.body)

      expect(controller.response).to have_http_status(:ok)
      expect(payload["results"].map { |asset| asset["uuid"] }).to contain_exactly(first.uuid, second.uuid)
    end

    it "lists active assets and requires authentication" do
      asset = asset_with_version(title: "Listed")
      get "/api/v1/assets", as: :json
      expect(response).to have_http_status(:ok)
      expect(json.map { |item| item["uuid"] }).to include(asset.uuid)

      sign_out user
      get "/api/v1/assets", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts Pact-stub uploads and rejects missing files" do
      post "/api/v1/assets", headers: { "X-Pact-Stub" => "true" }, as: :json
      expect(response).to have_http_status(:accepted)
      expect(json["status"]).to eq("processing")

      post "/api/v1/assets", params: { title: "No file" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("No file provided")
    end

    it "creates an asset from a real multipart upload with parsed filename metadata" do
      file = fixture_file_upload(Rails.root.join("spec/fixtures/images/test-image.jpg"), "image/jpeg")

      expect do
        post "/api/v1/assets", params: {
          file: file,
          title: "Uploaded Hero",
          metadata: { "dc:creator" => "Studio", "blank" => "" }.to_json,
        }
      end.to change(Asset, :count).by(1)

      expect(response).to have_http_status(:accepted)
      created = Asset.find_by!(title: "Uploaded Hero")
      expect(created.properties).to include("dc:creator" => "Studio", "original_filename" => "test-image.jpg")
      expect(created.active_version).to be_present
    end

    it "accepts plain hash metadata payloads and attaches the upload outside test mode" do
      file = fixture_file_upload(Rails.root.join("spec/fixtures/images/test-image.jpg"), "image/jpeg")
      attachment = instance_double(ActiveStorage::Attached::One, attach: true)
      controller = Api::V1::AssetsController.new
      controller.set_request!(ActionDispatch::TestRequest.create)
      controller.set_response!(ActionDispatch::TestResponse.new)
      allow(Rails.env).to receive(:test?).and_return(false)
      allow_any_instance_of(AssetVersion).to receive(:file).and_return(attachment)
      allow(controller).to receive(:params).and_return(
        { file: file, title: "Hash Metadata Upload", metadata: { "dc:creator" => "Hash Creator" } }
      )
      allow(controller).to receive(:active_resource_owner).and_return(user)

      controller.create

      expect(controller.response).to have_http_status(:accepted)
      created = Asset.find_by!(title: "Hash Metadata Upload")
      expect(created.properties).to include("dc:creator" => "Hash Creator")
      expect(attachment).to have_received(:attach)
    end

    it "ignores unsupported metadata payloads during upload" do
      file = fixture_file_upload(Rails.root.join("spec/fixtures/images/test-image.jpg"), "image/jpeg")
      allow_any_instance_of(Api::V1::AssetsController).to receive(:params).and_wrap_original do |original|
        params = original.call
        params[:metadata] = 123
        params
      end

      post "/api/v1/assets", params: { file: file, title: "Unsupported Metadata Upload" }

      expect(response).to have_http_status(:accepted)
      created = Asset.find_by!(title: "Unsupported Metadata Upload")
      expect(created.properties).to include("original_filename" => "test-image.jpg")
      expect(created.properties).not_to have_key("dc:creator")
    end

    it "applies active schema and product filename metadata during upload" do
      schema = create(:metadata_schema, :root, name: "Product Schema", slug: "product-schema")
      upload_path = Rails.root.join("spec/fixtures/images/test-image.jpg")
      file = Rack::Test::UploadedFile.new(upload_path, "image/jpeg", true, original_filename: "012993112028-en-FR01.jpg")

      post "/api/v1/assets", params: {
        file: file,
        schema_id: schema.id,
        metadata: { "dc:title" => "Schema Title", "blank" => "" },
      }

      expect(response).to have_http_status(:accepted)
      created = Asset.find_by!(uuid: json["id"])
      expect(created.title).to eq("012993112028-en-FR01.jpg")
      expect(created.properties).to include(
        "applied_schema_id" => schema.id,
        "applied_schema_slug" => "product-schema",
        "dam:product_id" => "012993112028",
        "dam:language_code" => "en",
        "dam:asset_type" => "FR01",
        "dc:title" => "Schema Title"
      )
      expect(created.properties).not_to have_key("blank")
    end

    it "ignores stale schema ids and uploads without inline metadata" do
      file = fixture_file_upload(Rails.root.join("spec/fixtures/images/test-image.jpg"), "image/jpeg")

      post "/api/v1/assets", params: { file: file, schema_id: -1 }

      expect(response).to have_http_status(:accepted)
      created = Asset.find_by!(uuid: json["id"])
      expect(created.properties).to include("original_filename" => "test-image.jpg")
      expect(created.properties).not_to have_key("applied_schema_id")
    end
  end

  describe "member read/update/delete endpoints" do
    it "shows an asset by uuid and returns 404 for a missing asset" do
      asset = asset_with_version(title: "Show Me")
      get "/api/v1/assets/#{asset.uuid}", as: :json
      expect(response).to have_http_status(:ok)
      expect(json["title"]).to eq("Show Me")
      # `properties` is the canonical shape AssetViewer/AssetExplorer expect
      # for the /folders?id= and /assets?id= deep-link flows — without it,
      # the AssetViewer can't tell the asset is an image and silently falls
      # back to the generic file icon instead of rendering the preview.
      expect(json["properties"]).to include("content_type" => "image/jpeg", "file_size" => 2048)
      expect(json["properties"]).to eq(json["metadata"])
      expect(json["content_type"]).to eq("image/jpeg")
      expect(json["size"]).to eq(2048)

      get "/api/v1/assets/not-a-real-uuid", as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "updates title, folder and metadata while snapshotting a version" do
      asset = asset_with_version(title: "Old")
      folder = create(:folder, user: user)

      expect do
        patch "/api/v1/assets/#{asset.uuid}", params: {
          asset: { title: "New", folder_id: folder.id, tags: %w[one two], metadata: { "dam:brand" => "Capri" } },
        }, as: :json
      end.to change { asset.asset_versions.count }.by(1)

      expect(response).to have_http_status(:ok)
      asset.reload
      expect(asset.title).to eq("New")
      expect(asset.folder_id).to eq(folder.id)
      expect(asset.properties).to include("dam:brand" => "Capri", "tags" => %w[one two])
    end

    it "moves an asset back to root without creating a metadata snapshot when only folder changes" do
      folder = create(:folder, user: user)
      asset = asset_with_version(title: "Move Root")
      asset.update!(folder: folder)

      expect do
        patch "/api/v1/assets/#{asset.uuid}", params: { asset: { folder_id: "root" } }, as: :json
      end.to change { asset.asset_versions.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(asset.reload.folder_id).to be_nil
      expect(asset.active_version.properties["metadata_snapshot"]).to eq({})
    end

    it "returns update errors for missing records and validation failures" do
      patch "/api/v1/assets/missing", params: { title: "Nope" }, as: :json
      expect(response).to have_http_status(:not_found)

      asset = asset_with_version(title: "Valid")
      allow_any_instance_of(Asset).to receive(:update!).and_raise(StandardError, "forced validation failure")
      patch "/api/v1/assets/#{asset.uuid}", params: { asset: { title: "Still Valid", metadata: { "x" => "y" } } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "updates metadata snapshots without an acting user or active version" do
      asset = create(:asset, user: user, title: "Detached", properties: { "existing" => "value" })
      controller = Api::V1::AssetsController.new
      controller.set_request!(ActionDispatch::TestRequest.create)
      controller.set_response!(ActionDispatch::TestResponse.new)
      allow(controller).to receive(:find_asset_record).and_return(asset)
      allow(controller).to receive(:check_asset_modify!)
      allow(controller).to receive(:performed?).and_return(false)
      allow(controller).to receive(:active_resource_owner).and_return(nil)
      allow(controller).to receive(:params).and_return(
        ActionController::Parameters.new(id: asset.uuid, asset: { metadata: { "dc:title" => "Updated" } })
      )

      controller.update

      expect(controller.response).to have_http_status(:ok)
      asset.reload
      expect(asset.active_version.created_by_id).to be_nil
      expect(asset.active_version.properties["metadata_snapshot"]).to eq("dc:title" => "Updated")
    end

    it "soft-deletes, restores and permanently deletes a trashed asset" do
      asset = asset_with_version(title: "Disposable")
      delete "/api/v1/assets/#{asset.uuid}", as: :json
      expect(response).to have_http_status(:ok)
      expect(asset.reload.deleted_at).to be_present

      post "/api/v1/assets/#{asset.uuid}/restore", as: :json
      expect(response).to have_http_status(:ok)
      expect(asset.reload.deleted_at).to be_nil

      asset.soft_delete
      storage = instance_double("StorageAdapter", delete: true)
      allow(StorageManager).to receive(:adapter_for).and_return(storage)
      delete "/api/v1/assets/#{asset.uuid}/permanent", as: :json
      expect(response).to have_http_status(:ok)
      expect(Asset.where(id: asset.id)).to be_empty
    end

    context "with a non-admin user and protected folders" do
      let(:user) { create(:user) }

      it "denies folder and asset operations without matching folder permissions" do
        protected_folder = create(:folder)
        asset = asset_with_version(title: "Private")
        asset.update!(folder: protected_folder)

        get "/api/v1/assets/#{asset.uuid}", as: :json
        expect(response).to have_http_status(:forbidden)

        patch "/api/v1/assets/#{asset.uuid}", params: { asset: { title: "Denied" } }, as: :json
        expect(response).to have_http_status(:forbidden)

        delete "/api/v1/assets/#{asset.uuid}", as: :json
        expect(response).to have_http_status(:forbidden)

        post "/api/v1/assets", params: { folder_id: protected_folder.id }, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "custom member actions" do
    it "returns versions, audit trail and restores a selected version" do
      asset = asset_with_version(title: "Versioned")
      old_version = asset.active_version
      new_version = create(:asset_version, asset: asset, version_number: 2, created_by: user, properties: { "size" => 4096 })
      asset.update!(active_version: new_version)

      get "/api/v1/assets/#{asset.uuid}/versions", as: :json
      expect(response).to have_http_status(:ok)
      expect(json["versions"].map { |v| v["version_number"] }).to eq([ 2, 1 ])

      get "/api/v1/assets/#{asset.uuid}/audit_trail", as: :json
      expect(response).to have_http_status(:ok)
      expect(json["audit_trail"].length).to eq(2)

      post "/api/v1/assets/#{asset.uuid}/versions/#{old_version.id}/restore", as: :json
      expect(response).to have_http_status(:ok)
      expect(asset.reload.active_version_id).to eq(old_version.id)
    end

    it "formats version history fallbacks when creator and size metadata are missing" do
      asset = asset_with_version(title: "Fallback Version")
      system_version = create(:asset_version, asset: asset, version_number: 2, created_by: nil, properties: {})
      asset.update!(active_version: system_version)

      get "/api/v1/assets/#{asset.uuid}/versions", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["versions"].first).to include("created_by" => "System User", "size" => "Unknown")
    end

    it "returns not found for a missing audit trail asset" do
      get "/api/v1/assets/missing/audit_trail", as: :json

      expect(response).to have_http_status(:not_found)
      expect(json["error"]).to eq("Asset not found")
    end

    it "purges the CDN for an asset through the legacy action" do
      asset = asset_with_version(title: "Purge Me")
      controller = build_assets_controller(id: asset.uuid)

      controller.purge_cdn
      payload = JSON.parse(controller.response.body)

      expect(controller.response).to have_http_status(:ok)
      expect(payload["message"]).to eq("CDN purge initiated.")
      expect(CdnInvalidationWorker).to have_received(:perform_async).with("asset", asset.uuid)
    end

    it "updates schema metadata and reports missing metadata targets" do
      asset = asset_with_version(title: "Metadata")
      patch "/api/v1/assets/#{asset.uuid}/metadata", params: { metadata: { "dc:description" => "Updated" }, schema_id: "7" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(asset.reload.properties).to include("dc:description" => "Updated", "applied_schema_id" => 7)

      patch "/api/v1/assets/missing/metadata", params: { metadata: { "x" => "y" } }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns metadata update validation errors" do
      asset = asset_with_version(title: "Broken Metadata")
      allow_any_instance_of(Asset).to receive(:update!).and_raise(StandardError, "metadata write failed")

      patch "/api/v1/assets/#{asset.uuid}/metadata", params: { metadata: { "dc:title" => "Broken" } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("metadata write failed")
    end

    it "checks hashes and lists exact and filename duplicates" do
      asset = asset_with_version(title: "Original", properties: { "checksum_sha256" => "dupe", "original_filename" => "same.jpg" })
      exact = asset_with_version(title: "Exact", properties: { "checksum_sha256" => "dupe", "original_filename" => "other.jpg" })
      name = asset_with_version(title: "Name", properties: { "checksum_sha256" => "different", "original_filename" => "same.jpg" })

      post "/api/v1/assets/check_hashes", params: { hashes: [ "dupe" ] }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json["duplicates"]["dupe"].map { |item| item["title"] }).to include("Original", "Exact")

      get "/api/v1/assets/#{asset.uuid}/duplicates", as: :json
      expect(response).to have_http_status(:ok)
      expect(json["duplicates"].map { |item| item["uuid"] }).to include(exact.uuid, name.uuid)
    end

    it "returns no duplicates when checksum and filename metadata are absent" do
      asset = asset_with_version(title: "Unique", properties: { "checksum_sha256" => nil, "original_filename" => nil })

      get "/api/v1/assets/#{asset.uuid}/duplicates", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["duplicates"]).to eq([])
    end

    it "returns not found when duplicate candidates are requested for a missing asset" do
      get "/api/v1/assets/missing/duplicates", as: :json

      expect(response).to have_http_status(:not_found)
      expect(json["error"]).to eq("Asset not found")
    end

    it "covers AI analysis completed, queued and enqueue branches" do
      completed = asset_with_version(title: "Analyzed", properties: { "ai_analysis" => { "labels" => [ "hero" ] } })
      post "/api/v1/assets/#{completed.uuid}/ai_analysis", as: :json
      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("completed")

      queued = asset_with_version(title: "Queued", properties: { "image_analysis_status" => "processing" })
      post "/api/v1/assets/#{queued.uuid}/ai_analysis", as: :json
      expect(response).to have_http_status(:accepted)
      expect(json["status"]).to eq("processing")

      fresh = asset_with_version(title: "Fresh")
      post "/api/v1/assets/#{fresh.uuid}/ai_analysis", as: :json
      expect(response).to have_http_status(:accepted)
      expect(fresh.reload.properties["image_analysis_status"]).to eq("queued")

      post "/api/v1/assets/missing/ai_analysis", as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "validates image processing params before doing disk work and rejects missing source files" do
      asset = asset_with_version(title: "Editable", properties: { "storage_path" => "missing/source.jpg" })
      post "/api/v1/assets/#{asset.uuid}/process_image", params: { crop_aspect: "9:9" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to include("Invalid crop aspect")

      post "/api/v1/assets/#{asset.uuid}/process_image", params: { crop_aspect: "free" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("Source file not found on disk.")
    end

    it "returns image processing validation and processing errors" do
      asset = processable_asset(title: "Processing Errors")
      processor = instance_double(ImageProcessingService)
      allow(ImageProcessingService).to receive(:new).and_return(processor)

      allow(processor).to receive(:process).and_raise(ImageProcessingService::ValidationError, "bad brightness")
      post "/api/v1/assets/#{asset.uuid}/process_image", params: { save_mode: "version" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to include("Invalid image parameters: bad brightness")

      allow(processor).to receive(:process).and_raise(ImageProcessingService::ProcessingError, "convert failed")
      post "/api/v1/assets/#{asset.uuid}/process_image", params: { save_mode: "version" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("Image processing failed. Please try again.")
    end

    it "returns not found when image processing cannot resolve an asset record" do
      controller = build_assets_controller(id: "missing")
      allow(controller).to receive(:find_asset_record).and_return(nil)

      controller.process_image

      expect(controller.response).to have_http_status(:not_found)
      expect(JSON.parse(controller.response.body)).to eq("error" => "Asset not found.")
    end

    it "processes images as a copy, an overwrite, and a first version when no active version exists" do
      processed_path = write_coverage_tmp_file("processed-copy.jpg", "processed")
      processor = instance_double(ImageProcessingService, process: processed_path)
      allow(ImageProcessingService).to receive(:new).and_return(processor)
      folder = create(:folder, user: user)

      copy_source = processable_asset(title: "Copy Source")
      expect do
        post "/api/v1/assets/#{copy_source.uuid}/process_image", params: {
          save_mode: "new",
          target_folder_id: folder.id,
          adjustments: { brightness: "10" },
          geometry: { rotate: "90", flip_horizontal: "true", focal_point: { x: "25.5", y: "75" } },
          crop_aspect: "1:1",
          filter: "Sepia",
          custom_cli: "-strip",
        }, as: :json
      end.to change(Asset, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(json["title"]).to eq("Copy Source (Copy)")
      expect(json["folder_id"]).to eq(folder.id)

      overwrite_source = processable_asset(title: "Overwrite Source")
      post "/api/v1/assets/#{overwrite_source.uuid}/process_image", params: {
        save_mode: "overwrite",
        target_folder_id: folder.id,
      }, as: :json
      expect(response).to have_http_status(:ok)
      expect(overwrite_source.reload.folder_id).to eq(folder.id)
      expect(overwrite_source.active_version.properties["storage_path"]).to eq(processed_path)

      no_version = create(:asset, user: user, title: "No Version", properties: {
        "storage_path" => write_coverage_tmp_file("no-version-source.jpg", "source"),
        "content_type" => "image/jpeg",
      })
      post "/api/v1/assets/#{no_version.uuid}/process_image", params: { save_mode: "overwrite" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(no_version.reload.active_version).to be_present
    end

    it "copies processed images into the source folder when no target folder is supplied" do
      processed_path = write_coverage_tmp_file("processed-same-folder.jpg", "processed")
      processor = instance_double(ImageProcessingService, process: processed_path)
      allow(ImageProcessingService).to receive(:new).and_return(processor)

      folder = create(:folder, user: user)
      source = processable_asset(title: "Copy Same Folder")
      source.update!(folder: folder)

      expect do
        post "/api/v1/assets/#{source.uuid}/process_image", params: { save_mode: "new" }, as: :json
      end.to change(Asset, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json["folder_id"]).to eq(folder.id)
    end

    it "processes images as in-place and branched new versions" do
      processed_path = write_coverage_tmp_file("processed-version.jpg", "processed")
      processor = instance_double(ImageProcessingService, process: processed_path)
      allow(ImageProcessingService).to receive(:new).and_return(processor)
      asset = processable_asset(title: "Version Source")

      post "/api/v1/assets/#{asset.uuid}/process_image", params: { save_mode: "version" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(asset.reload.active_version.version_number).to eq(2)
      expect(asset.active_version.properties["editor_state"]["crop_aspect"]).to eq("free")

      folder = create(:folder, user: user)
      expect do
        post "/api/v1/assets/#{asset.uuid}/process_image", params: {
          save_mode: "version",
          target_folder_id: folder.id,
        }, as: :json
      end.to change(Asset, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(json["folder_id"]).to eq(folder.id)
    end

    it "rejects watermarking for non-images and local serving without storage path" do
      asset = asset_with_version(title: "Pdf", properties: { "content_type" => "application/pdf" })
      get "/api/v1/assets/#{asset.uuid}/watermarked", as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      get "/api/v1/assets/local/#{asset.uuid}", as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "streams and caches local files from DAM storage" do
      dam_path = Rails.root.join("storage/dam/assets_controller_coverage/local.txt")
      FileUtils.mkdir_p(dam_path.dirname)
      File.binwrite(dam_path, "local body")
      asset = asset_with_version(title: "Local", properties: {
        "storage_path" => "assets_controller_coverage/local.txt",
        "content_type" => "text/plain",
      })

      get "/api/v1/assets/local/#{asset.uuid}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("local body")
      expect(response.headers["ETag"]).to be_present

      get "/api/v1/assets/local/#{asset.uuid}", headers: { "If-None-Match" => response.headers["ETag"] }
      expect(response).to have_http_status(:not_modified)
    ensure
      FileUtils.rm_f(dam_path)
      FileUtils.rm_rf(dam_path.dirname) if defined?(dam_path) && dam_path.dirname.to_s.end_with?("assets_controller_coverage")
    end

    it "falls back to asset-level storage for preview requests and honors If-Modified-Since" do
      dam_path = Rails.root.join("storage/dam/assets_controller_coverage/fallback-preview.txt")
      FileUtils.mkdir_p(dam_path.dirname)
      File.binwrite(dam_path, "preview fallback")
      asset = create(:asset, user: user, title: "Previewless", properties: {
        "storage_path" => "assets_controller_coverage/fallback-preview.txt",
        "content_type" => "text/plain",
      })

      get "/api/v1/assets/local/#{asset.uuid}", params: { variant: "preview" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("preview fallback")

      get "/api/v1/assets/local/#{asset.uuid}",
          params: { variant: "preview" },
          headers: { "If-Modified-Since" => 5.minutes.from_now.httpdate }
      expect(response).to have_http_status(:not_modified)
    ensure
      FileUtils.rm_f(dam_path)
      FileUtils.rm_rf(dam_path.dirname) if defined?(dam_path) && dam_path.dirname.to_s.end_with?("assets_controller_coverage")
    end

    it "redirects to an attached ActiveStorage file when present" do
      # NOTE: AssetVersion/Asset use UUID primary keys while
      # active_storage_attachments.record_id is a bigint column, so real
      # ActiveStorage attachment/lookup round-trips are unreliable in this
      # schema. We stub the attachment so this exercises the redirect branch
      # (AssetsController#local) deterministically instead of depending on
      # that pre-existing schema mismatch.
      asset = asset_with_version(title: "Attached Local", properties: { "storage_path" => "unused.txt" })
      attachment = instance_double(ActiveStorage::Attached::One, attached?: true)
      allow_any_instance_of(AssetVersion).to receive(:file).and_return(attachment)
      allow_any_instance_of(Api::V1::AssetsController).to receive(:url_for)
        .with(attachment).and_return("http://www.example.com/rails/active_storage/blobs/redirect/abc/test-image.jpg")

      get "/api/v1/assets/local/#{asset.uuid}"

      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to include("/rails/active_storage/")
    end

    it "streams files from the tmp staging area and reports missing files" do
      staging_path = write_coverage_tmp_file("staged.txt", "staging body")
      staged = asset_with_version(title: "Staged", properties: {
        "storage_path" => staging_path,
        "content_type" => "text/plain",
      })
      missing = asset_with_version(title: "Missing Disk", properties: {
        "storage_path" => "assets_controller_coverage/missing.txt",
        "content_type" => "text/plain",
      })

      get "/api/v1/assets/local/#{staged.uuid}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("staging body")

      get "/api/v1/assets/local/#{missing.uuid}", as: :json
      expect(response).to have_http_status(:not_found)
      expect(json["error"]).to eq("File missing from disk")
      expect(json["looked_at"]).to include("storage/dam/assets_controller_coverage/missing.txt")
    end

    it "serves the generated web preview when variant=preview is requested" do
      preview_path = Rails.root.join("storage/dam/assets_controller_coverage/preview.png")
      original_path = Rails.root.join("storage/dam/assets_controller_coverage/original.psd")
      FileUtils.mkdir_p(preview_path.dirname)
      File.binwrite(preview_path, "PNGPREVIEW")
      File.binwrite(original_path, "8BPS-original")
      asset = asset_with_version(title: "Psd", properties: {
        "storage_path"         => "assets_controller_coverage/original.psd",
        "content_type"         => "image/vnd.adobe.photoshop",
        "preview_storage_path" => "assets_controller_coverage/preview.png",
        "preview_content_type" => "image/png",
      })

      get "/api/v1/assets/local/#{asset.uuid}", params: { variant: "preview" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("PNGPREVIEW")
      expect(response.headers["Content-Type"]).to include("image/png")

      # Without the variant the original binary is served.
      get "/api/v1/assets/local/#{asset.uuid}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("8BPS-original")
    ensure
      FileUtils.rm_f(preview_path)
      FileUtils.rm_f(original_path)
      FileUtils.rm_rf(preview_path.dirname) if defined?(preview_path) && preview_path.dirname.to_s.end_with?("assets_controller_coverage")
    end

    it "exposes a preview_url that points at the preview variant" do
      asset = asset_with_version(title: "PsdMeta", properties: {
        "storage_path"         => "assets_controller_coverage/original.psd",
        "content_type"         => "image/vnd.adobe.photoshop",
        "preview_storage_path" => "assets_controller_coverage/preview.png",
        "preview_content_type" => "image/png",
      })

      get "/api/v1/assets/#{asset.uuid}", as: :json
      expect(response).to have_http_status(:ok)
      expect(json["preview_url"]).to include("variant=preview")
      expect(json["url"]).not_to include("variant=preview")
    end

    it "marks a PSD asset as not editable (the Image Editor cannot render it natively) but a JPEG as editable" do
      psd = asset_with_version(title: "Psd", properties: { "content_type" => "image/vnd.adobe.photoshop" })
      jpeg = asset_with_version(title: "Jpeg", properties: { "content_type" => "image/jpeg" })

      get "/api/v1/assets/#{psd.uuid}", as: :json
      expect(json["editable"]).to be(false)

      get "/api/v1/assets/#{jpeg.uuid}", as: :json
      expect(json["editable"]).to be(true)
    end

    it "generates and reports failures for watermarked images" do
      require "mini_magick"

      asset = asset_with_version(title: "Watermark", properties: {
        "storage_path" => "watermark.jpg",
        "content_type" => "image/jpeg",
      })
      image = instance_double(MiniMagick::Image, to_blob: "watermarked-bytes")
      options = double("MiniMagick options", gravity: nil, fill: nil, font: nil, pointsize: nil, annotate: nil)
      allow(image).to receive(:combine_options).and_yield(options)
      allow(MiniMagick::Image).to receive(:open).and_return(image)

      get "/api/v1/assets/#{asset.uuid}/watermarked"
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("watermarked-bytes")

      allow(MiniMagick::Image).to receive(:open).and_raise(StandardError, "boom")
      get "/api/v1/assets/#{asset.uuid}/watermarked", as: :json
      expect(response).to have_http_status(:internal_server_error)
      expect(json["error"]).to eq("Failed to generate secure proxy.")
    end

    it "watermarks asset-level images even when no active version is selected" do
      require "mini_magick"

      asset = create(:asset, user: user, title: "Standalone", properties: {
        "storage_path" => "standalone.jpg",
        "content_type" => "image/jpeg",
      })
      image = instance_double(MiniMagick::Image, to_blob: "asset-level-bytes")
      options = double("MiniMagick options", gravity: nil, fill: nil, font: nil, pointsize: nil, annotate: nil)
      allow(image).to receive(:combine_options).and_yield(options)
      allow(MiniMagick::Image).to receive(:open).and_return(image)

      get "/api/v1/assets/#{asset.uuid}/watermarked"

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("watermarked_v_Standalone.jpg")
      expect(response.body).to eq("asset-level-bytes")
    end

    it "returns empty workflow history when no workflows are attached" do
      asset = asset_with_version(title: "Workflowless")
      get "/api/v1/assets/#{asset.uuid}/workflow_history", as: :json
      expect(response).to have_http_status(:ok)
      expect(json).to include("active" => false, "instances" => [], "tasks" => [])
    end

    it "serializes active workflow instances, task ownership and admin cancellation capability" do
      asset = asset_with_version(title: "Workflowed")
      workflow = create(:workflow, name: "Approval Flow")
      step = create(:workflow_step, workflow: workflow, title: "Legal Review")
      instance = create(:workflow_instance, asset: asset, workflow: workflow, started_at: 1.hour.ago)
      task = create(:workflow_task, workflow_instance: instance, workflow_step: step, user: user, comment: "Please approve")
      completed = create(:workflow_instance, asset: asset, workflow: workflow, status: "completed", completed_at: Time.current, cancelled_by: user)

      get "/api/v1/assets/#{asset.uuid}/workflow_history", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["active"]).to be(true)
      expect(json["instance_status"]).to eq("in_progress")
      expect(json["tasks"].first).to include(
        "id" => task.id,
        "step_name" => "Legal Review",
        "user_name" => user.email,
        "is_current_user" => true,
        "is_pending" => true
      )
      active_payload = json["instances"].detect { |payload| payload["instance_id"] == instance.id }
      completed_payload = json["instances"].detect { |payload| payload["instance_id"] == completed.id }
      expect(active_payload).to include("workflow_name" => "Approval Flow", "can_force_cancel" => true)
      expect(completed_payload).to include("can_force_cancel" => false, "cancelled_by" => user.email)
    end

    it "lists trashed folders and assets through the legacy bin action" do
      trashed_folder = create(:folder, :trashed, user: user, name: "Deleted Folder")
      trashed_asset = asset_with_version(title: "Deleted Asset", properties: { "format" => "jpg" })
      trashed_asset.soft_delete
      controller = build_assets_controller

      controller.bin
      payload = JSON.parse(controller.response.body)

      expect(controller.response).to have_http_status(:ok)
      expect(payload["folders"]).to include(include("id" => trashed_folder.id, "name" => "Deleted Folder"))
      expect(payload["assets"]).to include(include("id" => trashed_asset.id, "title" => "Deleted Asset", "name" => "Deleted Asset"))
      expect(payload["breadcrumbs"]).to eq([ { "id" => "bin", "name" => "Trash Bin" } ])
    end

    it "handles bin assets without an active version" do
      orphaned = create(:asset, :trashed, user: user, title: "No Version", properties: { "storage_path" => "orphaned.txt" })
      controller = build_assets_controller

      controller.bin
      payload = JSON.parse(controller.response.body)

      expect(controller.response).to have_http_status(:ok)
      expect(payload["assets"]).to include(include("id" => orphaned.id, "properties" => include("storage_path" => "orphaned.txt")))
    end

    it "returns forbidden duplicate and AI-analysis requests for unreadable assets" do
      protected_folder = create(:folder)
      asset = asset_with_version(title: "Restricted")
      asset.update!(folder: protected_folder)

      sign_out user
      sign_in create(:user)

      get "/api/v1/assets/#{asset.uuid}/duplicates", as: :json
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/assets/#{asset.uuid}/ai_analysis", as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/assets/:id/metadata_schema" do
    let(:schema) do
      create(:metadata_schema, :root, :with_basic_tab, name: "Image",
             is_builtin: true, slug: "default")
    end

    def photo_asset(extra = {})
      asset_with_version(title: "Photo", properties: {
        "content_type"       => "image/jpeg",
        "applied_schema_id"  => schema.id,
        "embedded_metadata"  => { "XMP" => { "Title" => "Sunset over the bay" } },
      }.merge(extra))
    end

    it "returns the applied schema pre-filled from embedded metadata" do
      asset = photo_asset

      get "/api/v1/assets/#{asset.uuid}/metadata_schema", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(schema.id)
      expect(json["applied_schema_id"]).to eq(schema.id)
      title_field = json["resolved_tabs"].flat_map { |t| t["fields"] }
                                         .detect { |f| f["map_to_property"] == "dc:title" }
      expect(title_field["value"]).to eq("Sunset over the bay")
    end

    it "prefers a saved property value over the embedded default" do
      asset = photo_asset("dc:title" => "Curated Title")

      get "/api/v1/assets/#{asset.uuid}/metadata_schema", as: :json

      expect(response).to have_http_status(:ok)
      title_field = json["resolved_tabs"].flat_map { |t| t["fields"] }
                                         .detect { |f| f["map_to_property"] == "dc:title" }
      expect(title_field["value"]).to eq("Curated Title")
    end

    it "accepts a numeric asset id as well as a uuid" do
      asset = photo_asset

      get "/api/v1/assets/#{asset.id}/metadata_schema", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["asset_uuid"]).to eq(asset.uuid)
    end

    it "returns 404 for an unknown asset" do
      get "/api/v1/assets/does-not-exist/metadata_schema", as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when no schema can be resolved" do
      asset = asset_with_version(title: "Orphan", properties: { "content_type" => "image/jpeg" })

      get "/api/v1/assets/#{asset.uuid}/metadata_schema", as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "resolves a schema from the asset folder assignment" do
      folder = create(:folder, user: user)
      folder_schema = create(:metadata_schema, :root, :with_basic_tab, name: "Folder Schema")
      create(:metadata_schema_folder_assignment, metadata_schema: folder_schema, folder_id: folder.id)
      asset = asset_with_version(title: "Folder Scoped", properties: { "content_type" => "image/jpeg" })
      asset.update!(folder: folder, properties: asset.properties.except("applied_schema_id"))

      get "/api/v1/assets/#{asset.uuid}/metadata_schema", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(folder_schema.id)
      expect(json["applied_schema_id"]).to eq(folder_schema.id)
    end

    it "falls back to MIME resolution when an applied schema id is stale" do
      asset = asset_with_version(title: "Stale Applied", properties: {
        "content_type" => "image/jpeg",
        "applied_schema_id" => 99_999,
      })
      allow(MetadataSchema).to receive(:resolve_for_mime).with("image/jpeg").and_return(schema)

      get "/api/v1/assets/#{asset.uuid}/metadata_schema", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(schema.id)
    end

    it "falls back to MIME resolution when folder assignments are missing or stale" do
      folder = create(:folder, user: user)
      asset = asset_with_version(title: "Folder Fallback", properties: { "content_type" => "image/jpeg" })
      asset.update!(folder: folder, properties: asset.properties.except("applied_schema_id"))
      stale_schema = create(:metadata_schema, :root, name: "Stale Folder Schema")
      create(:metadata_schema_folder_assignment, folder_id: folder.id, metadata_schema: stale_schema)
      stale_schema.update_column(:deleted_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
      allow(MetadataSchema).to receive(:resolve_for_mime).with("image/jpeg").and_return(schema)

      get "/api/v1/assets/#{asset.uuid}/metadata_schema", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(schema.id)
    end
  end

  describe "GET /api/v1/assets/:id/stats and POST /api/v1/assets/:id/track_event" do
    it "starts at zero and increments per event type independently" do
      asset = asset_with_version(title: "Stats Asset")

      get "/api/v1/assets/#{asset.uuid}/stats", as: :json
      expect(response).to have_http_status(:ok)
      expect(json).to eq("views" => 0, "downloads" => 0, "shares" => 0)

      post "/api/v1/assets/#{asset.uuid}/track_event", params: { event: "view" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json).to eq("views" => 1, "downloads" => 0, "shares" => 0)

      post "/api/v1/assets/#{asset.uuid}/track_event", params: { event: "view" }, as: :json
      post "/api/v1/assets/#{asset.uuid}/track_event", params: { event: "download" }, as: :json
      post "/api/v1/assets/#{asset.uuid}/track_event", params: { event: "share" }, as: :json

      get "/api/v1/assets/#{asset.uuid}/stats", as: :json
      expect(json).to eq("views" => 2, "downloads" => 1, "shares" => 1)

      expect(
        AssetUsageEvent.where(asset_id: asset.id, user: user).pluck(:event_type).tally
      ).to eq("view" => 2, "download" => 1, "share" => 1)
    end

    it "rejects an unsupported event name" do
      asset = asset_with_version(title: "Bad Event Asset")

      post "/api/v1/assets/#{asset.uuid}/track_event", params: { event: "print" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("Unsupported event: print")
    end

    it "returns 404 for both endpoints when the asset does not exist" do
      get "/api/v1/assets/does-not-exist/stats", as: :json
      expect(response).to have_http_status(:not_found)

      post "/api/v1/assets/does-not-exist/track_event", params: { event: "view" }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "records a confirmed download event when the watermarked proxy is streamed" do
      asset = asset_with_version(title: "Watermarked Stats", properties: { "content_type" => "image/jpeg", "storage_path" => "helpers/file.jpg" })
      allow_any_instance_of(MiniMagick::Image).to receive(:combine_options)
      allow_any_instance_of(MiniMagick::Image).to receive(:to_blob).and_return("binary-data")
      allow(MiniMagick::Image).to receive(:open).and_return(instance_double(MiniMagick::Image, combine_options: nil, to_blob: "binary-data"))

      get "/api/v1/assets/#{asset.uuid}/watermarked", as: :json

      expect(response).to have_http_status(:ok)
      expect(
        AssetUsageEvent.where(asset_id: asset.id, event_type: "download").count
      ).to eq(1)
    end
  end

  describe "private helper coverage" do
    let(:controller) { Api::V1::AssetsController.new }

    it "resolves the OAuth resource owner and falls back to the first user" do
      oauth_user = create(:user)
      allow(controller).to receive(:user_signed_in?).and_return(false)
      allow(controller).to receive(:doorkeeper_token).and_return(instance_double("DoorkeeperToken", resource_owner_id: oauth_user.id))
      expect(controller.send(:active_resource_owner)).to eq(oauth_user)

      allow(controller).to receive(:doorkeeper_token).and_return(nil)
      expect(controller.send(:active_resource_owner)).to eq(User.first)
      expect(User.first).to eq(user)
    end

    it "treats empty collections as blank but scalar values as present" do
      expect(controller.send(:asset_metadata_blank?, [])).to be(true)
      expect(controller.send(:asset_metadata_blank?, 5)).to be(false)
    end

    it "normalizes update metadata payloads for plain hashes and missing assets" do
      allow(controller).to receive(:params).and_return(
        { asset: { "metadata" => { "dc:title" => "Hash Title" }, "tags" => %w[hero banner] } }
      )
      expect(controller.send(:update_metadata_payload)).to eq(
        "dc:title" => "Hash Title",
        "tags" => %w[hero banner]
      )

      allow(controller).to receive(:params).and_return({ title: "Top Level Only" })
      expect(controller.send(:update_metadata_payload)).to eq({})
    end

    it "covers filename parsing, worker dispatch, and asset-level helper fallbacks" do
      asset = create(:asset, user: user, status: "ready", properties: {
        "storage_path" => "helpers/file.txt",
        "content_type" => "text/plain",
      })
      schema_record = create(:metadata_schema, :root, name: "Unmapped", tabs: [
        { "name" => "General", "fields" => [ { "label" => "Notes" } ] },
      ])
      allow(schema_record).to receive(:resolved_tabs).and_return(schema_record.tabs)

      expect(controller.send(:parse_product_filename, nil)).to be_nil
      expect(controller.send(:parse_product_filename, "123-en-invalid.jpg")).to be_nil
      expect(controller.send(:resolve_source_file_path, asset)).to eq(Rails.root.join("storage/dam/helpers/file.txt").to_s)
      expect(controller.send(:format_asset, asset)).to include(version: 1, content_type: "text/plain")
      expect(controller.send(:merged_asset_properties, asset)).to include("storage_path" => "helpers/file.txt")
      expect(controller.send(:folder_path_for, double(path_hierarchy: [ { name: "Root" }, { name: "Child" } ]))).to eq("/Root/Child")
      expect(controller.send(:normalised_asset_status, double(
        attributes_before_type_cast: { "status" => "queued_review" },
        :[] => nil,
        status: "ready"
      ))).to eq("queued_review")

      serialized = controller.send(:serialize_asset_schema, schema_record, asset)
      expect(serialized[:resolved_tabs].first["fields"].first["value"]).to be_nil

      hide_const("AssetProcessorWorker")
      hide_const("CdnInvalidationWorker")
      hide_const("EdgeMetadataSyncWorker")
      expect { controller.send(:dispatch_asset_workers, asset, build_stubbed(:asset_version), "file.txt") }.not_to raise_error
    end
  end
end
