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
  before { sign_in user }

  it "categorizes mime types, storage, workflows and AI insights" do
    create(:asset, user: user, title: "Video", status: :draft, properties: { "content_type" => "video/mp4", "file_size" => "1048576" })
    create(:asset, user: user, status: :ready, properties: { "content_type" => "audio/mpeg", "file_size" => "0", "image_analysis_status" => "failed" })
    create(:asset, user: user, status: :ready, properties: { "content_type" => "application/pdf", "file_size" => "2048", "applied_schema_name" => "Core" })
    create(:asset, user: user, status: :ready, properties: { "content_type" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document" })

    get "/api/v1/dashboard/overview", as: :json
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["assets_by_type"].map { |row| row["type"] }).to include("Videos", "Audio", "PDF", "Documents")
    expect(body["storage"]["total_human"]).not_to eq("0 B")
    expect(body["ai_insights"].map { |i| i["key"] }).to include("failed_analysis", "no_schema", "recent_24h")
  end
end
