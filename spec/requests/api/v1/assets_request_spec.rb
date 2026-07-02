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

  after do
    FileUtils.rm_rf(Rails.root.join("tmp/assets_controller_coverage"))
  end

  describe "collection endpoints" do
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
  end

  describe "member read/update/delete endpoints" do
    it "shows an asset by uuid and returns 404 for a missing asset" do
      asset = asset_with_version(title: "Show Me")
      get "/api/v1/assets/#{asset.uuid}", as: :json
      expect(response).to have_http_status(:ok)
      expect(json["title"]).to eq("Show Me")

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

    it "updates schema metadata and reports missing metadata targets" do
      asset = asset_with_version(title: "Metadata")
      patch "/api/v1/assets/#{asset.uuid}/metadata", params: { metadata: { "dc:description" => "Updated" }, schema_id: "7" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(asset.reload.properties).to include("dc:description" => "Updated", "applied_schema_id" => 7)

      patch "/api/v1/assets/missing/metadata", params: { metadata: { "x" => "y" } }, as: :json
      expect(response).to have_http_status(:not_found)
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
  end
end
