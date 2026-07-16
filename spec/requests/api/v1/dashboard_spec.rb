# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Dashboard", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /api/v1/dashboard/overview" do
    context "when authenticated" do
      before { create_list(:asset, 3, user: user) }

      it "returns 200 with all expected sections" do
        get "/api/v1/dashboard/overview", as: :json
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).to include("kpis", "asset_growth", "assets_by_type", "storage", "recent_assets", "workflow_summary", "ai_insights")
      end

      it "returns correct kpi structure" do
        get "/api/v1/dashboard/overview", as: :json
        kpis = JSON.parse(response.body)["kpis"]
        expect(kpis).to include("total_assets", "total_folders", "total_users", "assets_added_7d")
        expect(kpis["total_assets"]).to be_a(Integer)
      end

      it "returns asset growth with 6 monthly entries" do
        get "/api/v1/dashboard/overview", as: :json
        growth = JSON.parse(response.body)["asset_growth"]
        expect(growth).to be_an(Array)
        expect(growth.length).to eq(6)
        expect(growth.first).to include("month", "count")
      end

      it "returns storage with total_bytes and total_human" do
        get "/api/v1/dashboard/overview", as: :json
        storage = JSON.parse(response.body)["storage"]
        expect(storage).to include("total_bytes", "total_human")
      end

      it "returns recent_assets as array" do
        get "/api/v1/dashboard/overview", as: :json
        recent = JSON.parse(response.body)["recent_assets"]
        expect(recent).to be_an(Array)
        expect(recent.length).to be <= 20
      end

      it "returns ai_insights as array" do
        get "/api/v1/dashboard/overview", as: :json
        insights = JSON.parse(response.body)["ai_insights"]
        expect(insights).to be_an(Array)
      end
    end

    it "returns 401 when not authenticated" do
      sign_out user
      get "/api/v1/dashboard/overview", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

# ---- merged from dashboard_coverage_spec.rb ----
RSpec.describe "Api::V1::Dashboard coverage", type: :request do
  let(:user) { create(:user) }
  let(:controller) { Api::V1::DashboardController.new }

  before { sign_in user }

  it "categorizes mime types, storage, workflows and AI insights" do
    create(:asset, user: user, title: "Video", status: :draft, properties: { "content_type" => "video/mp4", "size" => "1048576" })
    create(:asset, user: user, status: :ready, properties: { "content_type" => "audio/mpeg", "size" => "0", "image_analysis_status" => "failed" })
    create(:asset, user: user, status: :ready, properties: { "content_type" => "application/pdf", "size" => "2048", "applied_schema_name" => "Core" })
    create(:asset, user: user, status: :ready, properties: { "content_type" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document" })

    get "/api/v1/dashboard/overview", as: :json
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["assets_by_type"].map { |row| row["type"] }).to include("Videos", "Audio", "PDF", "Documents")
    expect(body["storage"]["total_human"]).not_to eq("0 B")
    expect(body["ai_insights"].map { |i| i["key"] }).to include("failed_analysis", "no_schema", "recent_24h")
  end

  it "maps image and fallback mime buckets" do
    expect(controller.send(:simplify_mime, "image/png")).to eq("Images")
    expect(controller.send(:simplify_mime, "text/plain")).to eq("Other")
  end

  it "merges distinct raw content types into a single bucket entry (regression: duplicate pie slices)" do
    create(:asset, user: user, status: :ready, properties: { "content_type" => "image/jpeg" })
    create(:asset, user: user, status: :ready, properties: { "content_type" => "image/png" })
    create(:asset, user: user, status: :ready,
                   properties: { "content_type" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document" })
    create(:asset, user: user, status: :ready, properties: { "content_type" => "application/msword" })

    get "/api/v1/dashboard/overview", as: :json
    by_type = response.parsed_body["assets_by_type"]

    images_rows = by_type.select { |row| row["type"] == "Images" }
    documents_rows = by_type.select { |row| row["type"] == "Documents" }

    expect(images_rows.length).to eq(1)
    expect(images_rows.first["count"]).to eq(2)
    expect(documents_rows.length).to eq(1)
    expect(documents_rows.first["count"]).to eq(2)
  end

  it "sums the `size` property (not the unused `file_size` key) for storage and recent-asset sizes" do
    create(:asset, user: user, status: :ready, properties: { "content_type" => "image/jpeg", "size" => "1000" })
    create(:asset, user: user, status: :ready, properties: { "content_type" => "image/png", "size" => "2000" })

    get "/api/v1/dashboard/overview", as: :json
    body = response.parsed_body

    expect(body["storage"]["total_bytes"]).to eq(3000)
    expect(body["storage"]["total_human"]).not_to eq("0 B")
    expect(body["recent_assets"].map { |a| a["file_size"] }).to include(1000, 2000)
  end

  it "falls back to zero storage when the aggregate query returns no rows" do
    allow(ActiveRecord::Base.connection).to receive(:execute).and_return([])

    expect(controller.send(:build_storage)).to eq(total_bytes: 0, total_human: "0 B")
  end

  it "falls back to filenames and unknown metadata for recent assets" do
    asset_with_filename = instance_double(
      Asset,
      id: 1,
      uuid: "uuid-1",
      title: nil,
      properties: { "original_filename" => "cover.png", "content_type" => "image/png", "size" => "12" },
      created_at: Time.zone.parse("2026-07-03 10:00:00"),
      status: "ready"
    )
    untitled_asset = instance_double(
      Asset,
      id: 2,
      uuid: "uuid-2",
      title: nil,
      properties: nil,
      created_at: Time.zone.parse("2026-07-03 10:01:00"),
      status: nil
    )

    allow(Asset).to receive_message_chain(:active, :order, :limit).and_return([ asset_with_filename, untitled_asset ])

    expect(controller.send(:build_recent_assets)).to include(
      a_hash_including(title: "cover.png", content_type: "image/png", file_size: 12),
      a_hash_including(title: "Untitled", content_type: "unknown", file_size: 0, status: "draft")
    )
  end

  it "omits failed-analysis and no-schema insights when the counts are zero" do
    asset_active_scope = instance_double(ActiveRecord::Relation)
    failed_scope = instance_double(ActiveRecord::Relation, count: 0)
    schema_scope = instance_double(ActiveRecord::Relation, count: 0)
    recent_scope = instance_double(ActiveRecord::Relation, count: 1)

    allow(Asset).to receive(:active).and_return(asset_active_scope)
    allow(asset_active_scope).to receive(:where).with("properties->>'image_analysis_status' = 'failed'").and_return(failed_scope)
    allow(asset_active_scope).to receive(:where).with("properties->>'applied_schema_name' IS NULL").and_return(schema_scope)
    allow(asset_active_scope).to receive(:where).with("created_at >= ?", anything).and_return(recent_scope)

    result = controller.send(:build_ai_insights)

    expect(result).to eq([ { type: "success", key: "recent_24h", count: 1 } ])
  end
end
