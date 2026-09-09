# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Preservation", type: :request do
  let(:admin) { create(:user, admin: true) }
  let(:asset) { create(:asset) }

  def json = response.parsed_body

  before { sign_in admin }

  describe "GET /api/v1/preservation/fixity" do
    it "leads with coverage, not with how many checks happened to run" do
      version = create(:asset_version, asset: asset,
                                       properties: { "checksum_sha256" => "abc", "storage_path" => "a/b" })
      version.update_columns(last_fixity_check_at: 1.day.ago, fixity_status: "passed")
      create(:asset_version, asset: asset,
                             properties: { "checksum_sha256" => "def", "storage_path" => "a/c" })

      get "/api/v1/preservation/fixity", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["coverage"]).to include("verifiable" => 2, "checked" => 1, "never_checked" => 1)
      expect(json["coverage"]["coverage_percent"]).to eq(50.0)
      expect(json["recheck_after_days"]).to eq(90)
    end

    it "lists conclusive failures but not inconclusive reads" do
      version = create(:asset_version, asset: asset, properties: { "checksum_sha256" => "abc" })
      FixityCheck.create!(asset: asset, asset_version: version, status: "failed",
                          expected_checksum: "abc", actual_checksum: "zzz",
                          storage_path: "a/b", checked_at: Time.current)
      FixityCheck.create!(asset: asset, asset_version: version, status: "unreadable",
                          storage_path: "a/b", checked_at: Time.current)

      get "/api/v1/preservation/fixity", as: :json

      expect(json["recent_failures"].map { |f| f["status"] }).to eq([ "failed" ])
      expect(json["checks_last_24h"]).to eq(2)
    end

    it "refuses non-admins, because the report is a map of where the gaps are" do
      sign_out admin
      sign_in create(:user, admin: false)

      get "/api/v1/preservation/fixity", as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      sign_out admin

      get "/api/v1/preservation/fixity", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/preservation/verify" do
    it "reports versions with no digest as unverifiable rather than failed" do
      create(:asset_version, asset: asset, properties: { "storage_path" => "a/b" })

      post "/api/v1/preservation/verify", params: { asset_id: asset.id }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["skipped"]).to eq(1)
      expect(json["results"].first["status"]).to eq("unverifiable")
    end

    it "verifies by asset UUID as well as primary key" do
      version = create(:asset_version, asset: asset,
                                       properties: { "checksum_sha256" => "abc", "storage_path" => "a/b" })
      allow(Fixity::Verifier).to receive(:call).and_return(
        Fixity::Verifier::Result.new(status: "passed", check: nil, message: nil),
      )

      post "/api/v1/preservation/verify", params: { asset_id: asset.uuid }, as: :json

      expect(json["verified"]).to eq(1)
      expect(json["results"].first["version_id"]).to eq(version.id)
    end

    it "caps how much egress a single request can trigger" do
      30.times do |n|
        create(:asset_version, asset: asset, version_number: n + 1,
                               properties: { "checksum_sha256" => "abc", "storage_path" => "a/#{n}" })
      end
      allow(Fixity::Verifier).to receive(:call).and_return(
        Fixity::Verifier::Result.new(status: "passed", check: nil, message: nil),
      )

      post "/api/v1/preservation/verify", params: { asset_id: asset.id }, as: :json

      expect(json["results"].size).to eq(Api::V1::PreservationController::MAX_ON_DEMAND_VERSIONS)
    end

    it "404s for an unknown asset" do
      post "/api/v1/preservation/verify", params: { asset_id: SecureRandom.uuid }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/preservation/formats" do
    it "puts the formats that are already unreadable first" do
      create(:asset, properties: { "content_type" => "image/png" })
      create(:asset, properties: { "content_type" => "application/x-shockwave-flash" })

      get "/api/v1/preservation/formats", as: :json

      expect(response).to have_http_status(:ok)
      expect(json["formats"].first["content_type"]).to eq("application/x-shockwave-flash")
      expect(json["formats"].first["risk"]).to eq("high")
      expect(json["totals"]["high_risk"]).to eq(1)
    end
  end
end
