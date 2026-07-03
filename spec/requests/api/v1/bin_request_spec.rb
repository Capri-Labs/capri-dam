# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Bin coverage", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  before do
    sign_in admin
    allow(BinPurgeWorker).to receive(:perform_async) if defined?(BinPurgeWorker)
  end

  def json = response.parsed_body

  def trashed_asset(title, props = {})
    asset = create(:asset, :trashed, user: admin, title: title, properties: { "content_type" => "audio/mpeg", "size" => 1024 }.merge(props))
    version = create(:asset_version, asset: asset, properties: asset.properties)
    asset.update!(active_version: version)
    asset.update_column(:deleted_at, 45.days.ago)
    asset
  end

  it "filters document/video/audio-like bin items and clamps pagination" do
    doc = trashed_asset("Document", "content_type" => "application/vnd.ms-excel", "size" => 200)
    trashed_asset("Video", "content_type" => "video/mp4", "size" => 500)
    create(:folder, :trashed, user: admin, name: "Folder")

    get "/api/v1/bin", params: { type: "document", q: "Doc", sort: "size", direction: "asc", page: -1, per_page: 500 }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json["pagination"]).to include("page" => 1, "per_page" => 100)
    expect(json["items"].map { |i| i["id"] }).to contain_exactly(doc.uuid)

    get "/api/v1/bin", params: { type: "video" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json["items"].map { |i| i["media_type"] }).to all(eq("video"))
  end

  it "returns empty stats and requires auth" do
    get "/api/v1/bin/stats", as: :json
    expect(response).to have_http_status(:ok)
    expect(json).to include("total_items", "oldest_deleted_at", "retention_days")

    sign_out admin
    get "/api/v1/bin/stats", as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "uses asset property sizes in stats and falls back unknown media types to file" do
    versioned = trashed_asset("Versioned", "content_type" => "image/png", "size" => 256)
    fallback = create(
      :asset,
      :trashed,
      user: admin,
      title: "Binary",
      properties: { "content_type" => "application/octet-stream", "size" => 128 }
    )
    fallback.update_column(:deleted_at, 45.days.ago)

    get "/api/v1/bin/stats", as: :json

    expect(response).to have_http_status(:ok)
    expect(json["total_size_bytes"]).to eq(384)

    get "/api/v1/bin", params: { type: "asset" }, as: :json

    expect(response).to have_http_status(:ok)
    expect(json["items"]).to include(
      hash_including("id" => versioned.uuid, "media_type" => "image"),
      hash_including("id" => fallback.uuid, "media_type" => "file")
    )
  end

  it "falls back to asset properties when the active version metadata is missing and classifies audio files" do
    audio = trashed_asset("Podcast", "content_type" => "audio/mpeg", "size" => 512)
    audio.active_version.update_column(:properties, nil)

    get "/api/v1/bin/stats", as: :json
    expect(response).to have_http_status(:ok)
    expect(json["total_size_bytes"]).to eq(512)

    get "/api/v1/bin", params: { type: "asset" }, as: :json
    expect(json["items"]).to include(hash_including("id" => audio.uuid, "media_type" => "audio"))
  end

  it "bulk restores and destroys missing items with errors" do
    asset = trashed_asset("Restore Me")
    folder = create(:folder, :trashed, user: admin)

    post "/api/v1/bin/bulk_restore", params: { items: [ { id: asset.id, type: "asset" }, { id: folder.id, type: "folder" }, { id: 0, type: "asset" } ] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json["restored"]).to eq(2)
    expect(json["errors"]).not_to be_empty

    doomed = trashed_asset("Destroy Me")
    delete "/api/v1/bin/bulk_destroy", params: { items: [ { id: doomed.id, type: "asset" }, { id: 0, type: "folder" } ] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json["deleted"]).to eq(1)
    expect(json["errors"]).not_to be_empty
  end

  it "reports destroy failures when permanent deletion raises unexpectedly" do
    doomed = trashed_asset("Boom")
    allow_any_instance_of(Api::V1::BinController).to receive(:permanent_delete_asset).and_raise(StandardError, "kaboom") # rubocop:disable RSpec/AnyInstance

    delete "/api/v1/bin/bulk_destroy", params: { items: [ { id: doomed.id, type: "asset" } ] }, as: :json

    expect(response).to have_http_status(:ok)
    expect(json["deleted"]).to eq(0)
    expect(json["errors"]).to contain_exactly("Failed to delete asset ##{doomed.id}: kaboom")
    expect(doomed.reload).to be_present
  end

  it "empties the bin and returns retention policy" do
    trashed_asset("Empty Asset")
    create(:folder, :trashed, user: admin)
    allow(StorageManager).to receive(:adapter_for).and_return(instance_double("StorageAdapter", delete: true))

    delete "/api/v1/bin/empty", as: :json
    expect(response).to have_http_status(:ok)
    expect(json["deleted"]).to eq(2)

    get "/api/v1/bin/retention_policy", as: :json
    expect(response).to have_http_status(:ok)
    expect(json).to include("retention_days", "workflow_behavior", "next_scheduled_at")
  end

  it "empties storage-backed versions even when no storage adapter is available" do
    asset = trashed_asset("Detached", "storage_path" => "bin/detached.dat")

    delete "/api/v1/bin/empty", as: :json

    expect(response).to have_http_status(:ok)
    expect(Asset.exists?(asset.id)).to be(false)
  end

  it "updates policy for admins and forbids non-admin users" do
    sign_in user
    put "/api/v1/bin/retention_policy", params: { retention_days: 9 }, as: :json
    expect(response).to have_http_status(:forbidden)

    sign_in admin
    put "/api/v1/bin/retention_policy", params: { retention_days: 999, workflow_behavior: "force_terminate", batch_size: 999, notify_admins: true }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json).to include("retention_days" => 365, "batch_size" => 500, "notify_admins" => true)
  end

  it "keeps the action-level admin guards active when before_actions are bypassed" do
    allow_any_instance_of(Api::V1::BinController).to receive(:require_admin!).and_return(true) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Api::V1::BinController).to receive(:require_admin_scope!).and_return(true) # rubocop:disable RSpec/AnyInstance

    sign_in user

    put "/api/v1/bin/retention_policy", params: { retention_days: 9 }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(json).to eq("error" => "Administrator privileges required.")

    post "/api/v1/bin/trigger_purge", as: :json
    expect(response).to have_http_status(:forbidden)
    expect(json).to eq("error" => "Administrator privileges required.")
  end

  it "queues purge, detects conflicts and reports status" do
    post "/api/v1/bin/trigger_purge", as: :json
    expect(response).to have_http_status(:ok)
    expect(json["queued"]).to be(true)

    post "/api/v1/bin/trigger_purge", as: :json
    expect(response).to have_http_status(:conflict)

    Setting.set("bin_purge_last_results", { deleted: 2, skipped: 1 })
    get "/api/v1/bin/purge_status", as: :json
    expect(response).to have_http_status(:ok)
    expect(json["last_results"]).to include("deleted" => 2)
  end

  it "deletes stored files during permanent destroy and logs storage adapter failures" do
    backend = instance_double(StorageBackend)
    storage = instance_double("StorageAdapter")
    stored = trashed_asset("Stored", "storage_path" => "bin/stored.dat")
    broken = trashed_asset("Broken", "storage_path" => "bin/broken.dat")

    allow(StorageBackend).to receive(:find_by).with(active: true).and_return(backend)
    allow(StorageManager).to receive(:adapter_for).with(backend).and_return(storage)
    allow(storage).to receive(:delete).with("bin/stored.dat").and_return(true)
    allow(storage).to receive(:delete).with("bin/broken.dat").and_raise(StandardError, "storage offline")
    allow(Rails.logger).to receive(:warn)

    delete "/api/v1/bin/bulk_destroy", params: {
      items: [ { id: stored.id, type: "asset" }, { id: broken.id, type: "asset" } ],
    }, as: :json

    expect(response).to have_http_status(:ok)
    expect(json["deleted"]).to eq(2)
    expect(json["errors"]).to eq([])
    expect(StorageManager).to have_received(:adapter_for).with(backend).twice
    expect(storage).to have_received(:delete).with("bin/stored.dat")
    expect(storage).to have_received(:delete).with("bin/broken.dat")
    expect(Rails.logger).to have_received(:warn).with(include("storage offline"))
    expect(Asset.where(id: [ stored.id, broken.id ])).to be_empty
  end

  it "purges attached files during empty and permanent destroy flows" do
    backend = instance_double(StorageBackend)
    storage = instance_double("StorageAdapter", delete: true)
    empty_asset = trashed_asset("Empty Attached", "storage_path" => "bin/empty.txt")
    empty_asset.active_version.file.attach(io: StringIO.new("version"), filename: "empty.txt", content_type: "text/plain")

    allow(StorageBackend).to receive(:find_by).with(active: true).and_return(backend)
    allow(StorageManager).to receive(:adapter_for).with(backend).and_return(storage)

    delete "/api/v1/bin/empty", as: :json

    expect(response).to have_http_status(:ok)
    expect(storage).to have_received(:delete).with("bin/empty.txt")

    destroy_asset = trashed_asset("Destroy Attached")
    destroy_asset.active_version.file.attach(io: StringIO.new("version"), filename: "destroy.txt", content_type: "text/plain")
    destroy_asset.file.attach(io: StringIO.new("asset"), filename: "asset.txt", content_type: "text/plain")

    # NOTE: don't assert via ActiveStorage::Attachment.exists?(blob_id:) here —
    # active_storage_attachments.record_id is a bigint while Asset/AssetVersion
    # use UUID primary keys, so real attach/query round-trips against that
    # column are unreliable (the UUID gets silently truncated by Ruby's
    # String#to_i). Instead verify #purge was actually invoked on each file.
    # `permanent_delete_asset` re-fetches versions via `asset.asset_versions`,
    # yielding fresh AR objects, so stub at the class level to intercept them.
    version_file = destroy_asset.active_version.file
    asset_file   = destroy_asset.file
    allow_any_instance_of(AssetVersion).to receive(:file).and_return(version_file) # rubocop:disable RSpec/AnyInstance
    allow(destroy_asset).to receive(:file).and_return(asset_file)
    allow(version_file).to receive(:purge).and_call_original
    allow(asset_file).to receive(:purge).and_call_original

    controller = Api::V1::BinController.new
    allow(StorageBackend).to receive(:find_by).with(active: true).and_return(nil)

    controller.send(:permanent_delete_asset, destroy_asset)

    expect(version_file).to have_received(:purge)
    expect(asset_file).to have_received(:purge)
  end

  it "keeps admin-only actions forbidden when current_user resolves to nil" do
    allow_any_instance_of(Api::V1::BinController).to receive(:authenticate_hybrid!).and_return(true) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Api::V1::BinController).to receive(:require_admin!).and_return(true) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Api::V1::BinController).to receive(:require_admin_scope!).and_return(true) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Api::V1::BinController).to receive(:current_user).and_return(nil) # rubocop:disable RSpec/AnyInstance

    put "/api/v1/bin/retention_policy", params: { retention_days: 5 }, as: :json
    expect(response).to have_http_status(:forbidden)

    post "/api/v1/bin/trigger_purge", as: :json
    expect(response).to have_http_status(:forbidden)

    get "/api/v1/bin/ai/smart_suggestions", as: :json
    expect(response).to have_http_status(:forbidden)

    get "/api/v1/bin/ai/cleanup_report", as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "keeps pinned suggestions but gives them a lower heuristic score" do
    pinned = trashed_asset("Pinned", "size" => 8.megabytes)
    unpinned = trashed_asset("Unpinned", "size" => 8.megabytes)
    collection = create(:collection, user: admin)
    create(:collection_asset, collection: collection, asset: pinned, user: admin)

    get "/api/v1/bin/ai/smart_suggestions", as: :json

    scores = json["suggestions"].index_by { |item| item["id"] }
    expect(scores[pinned.id]["has_collection_pin"]).to be(true)
    expect(scores[pinned.id]["heuristic_score"]).to be < scores[unpinned.id]["heuristic_score"]
  end

  it "returns a same-day next_scheduled_at before the 03:00 UTC cutoff" do
    allow(Time).to receive(:current).and_return(Time.utc(2026, 7, 3, 1, 0, 0))

    get "/api/v1/bin/retention_policy", as: :json

    expect(response).to have_http_status(:ok)
    expect(json["next_scheduled_at"]).to eq("2026-07-03T03:00:00Z")
  end

  it "returns AI cleanup suggestions/report for admins and forbids non-admins" do
    trashed_asset("Old Large", "size" => 5.megabytes)

    get "/api/v1/bin/ai/smart_suggestions", params: { limit: 1 }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json).to include("suggestions", "ai_available")

    get "/api/v1/bin/ai/cleanup_report", as: :json
    expect(response).to have_http_status(:ok)
    expect(json["report"]).to include("summary", "next_actions")

    sign_in user
    get "/api/v1/bin/ai/smart_suggestions", as: :json
    expect(response).to have_http_status(:forbidden)
    get "/api/v1/bin/ai/cleanup_report", as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
