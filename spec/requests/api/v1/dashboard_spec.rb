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
        expect(recent.length).to be <= 10
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
