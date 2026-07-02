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

  it "updates policy for admins and forbids non-admin users" do
    sign_in user
    put "/api/v1/bin/retention_policy", params: { retention_days: 9 }, as: :json
    expect(response).to have_http_status(:forbidden)

    sign_in admin
    put "/api/v1/bin/retention_policy", params: { retention_days: 999, workflow_behavior: "force_terminate", batch_size: 999, notify_admins: true }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json).to include("retention_days" => 365, "batch_size" => 500, "notify_admins" => true)
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
