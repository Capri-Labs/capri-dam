# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Api::V1::Dashboard Docs", type: :request do
  path "/api/v1/dashboard/overview" do
    get "Get dashboard overview statistics" do
      tags "Dashboard"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "dashboard statistics" do
        schema type: :object,
               required: %w[kpis asset_growth assets_by_type storage recent_assets workflow_summary ai_insights],
               properties: {
                 kpis: { type: :object },
                 asset_growth: { type: :array, items: { type: :object } },
                 assets_by_type: { type: :array, items: { type: :object } },
                 storage: { type: :object },
                 recent_assets: { type: :array, items: { type: :object } },
                 workflow_summary: { type: :object },
                 ai_insights: { type: :array, items: { type: :object } },
               }

        run_test!
      end

      response "401", "unauthorized" do
        schema type: :object,
               properties: {
                 error: { type: :string },
               }

        run_test!
      end
    end
  end
end
