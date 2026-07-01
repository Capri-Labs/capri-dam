# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Assets analysis", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user, :admin) }
  let(:folder) { create(:folder, user: user, name: "Marketing") }

  before do
    ActiveJob::Base.queue_adapter = :test
    sign_in(user)
    clear_enqueued_jobs
  end

  describe "GET /api/v1/assets/:id/duplicates" do
    let!(:asset) do
      create(
        :asset,
        user: user,
        folder: folder,
        title: "Hero Banner",
        properties: { "original_filename" => "hero-banner.jpg" }
      )
    end
    let!(:asset_version) do
      create(
        :asset_version,
        :with_checksum,
        asset: asset,
        properties: {
          "checksum_sha256" => "shared-checksum",
          "content_type" => "image/jpeg",
          "size" => 1024,
        },
      )
    end

    let!(:exact_duplicate) do
      create(
        :asset,
        user: user,
        folder: folder,
        title: "Hero Banner Copy",
        properties: { "original_filename" => "hero-banner-copy.jpg" }
      )
    end
    let!(:exact_duplicate_version) do
      create(
        :asset_version,
        asset: exact_duplicate,
        properties: {
          "checksum_sha256" => "shared-checksum",
          "content_type" => "image/jpeg",
          "size" => 2048,
        },
      )
    end

    let!(:name_duplicate) do
      create(
        :asset,
        user: user,
        title: "Hero Banner Variant",
        properties: { "original_filename" => "hero-banner.jpg" }
      )
    end
    let!(:name_duplicate_version) do
      create(
        :asset_version,
        asset: name_duplicate,
        properties: {
          "checksum_sha256" => "other-checksum",
          "content_type" => "image/jpeg",
          "size" => 512,
        },
      )
    end

    before do
      asset.update!(active_version: asset_version)
      exact_duplicate.update!(active_version: exact_duplicate_version)
      name_duplicate.update!(active_version: name_duplicate_version)
    end

    it "returns duplicate candidates with similarity metadata" do
      get "/api/v1/assets/#{asset.id}/duplicates"

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body["duplicates"].size).to eq(2)
      expect(body["duplicates"]).to include(
        a_hash_including(
          "id" => exact_duplicate.id,
          "similarity_type" => "exact",
          "similarity_score" => 100
        ),
        a_hash_including(
          "id" => name_duplicate.id,
          "similarity_type" => "name_match",
          "similarity_score" => 84
        )
      )
    end
  end

  describe "POST /api/v1/assets/:id/ai_analysis" do
    let!(:asset) do
      create(
        :asset,
        user: user,
        title: "Brand Overview",
        properties: { "original_filename" => "brand-overview.pdf" }
      )
    end
    let!(:asset_version) do
      create(
        :asset_version,
        asset: asset,
        properties: { "content_type" => "application/pdf", "size" => 4096 }
      )
    end

    before do
      asset.update!(active_version: asset_version)
    end

    it "queues analysis when none exists yet" do
      expect do
        post "/api/v1/assets/#{asset.id}/ai_analysis"
      end.to have_enqueued_job(Assets::AiAnalysisJob).with(asset.id)

      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)).to include("status" => "queued")
      expect(asset.reload.properties["image_analysis_status"]).to eq("queued")
    end

    it "returns completed analysis when stored properties are present" do
      asset.update!(
        properties: asset.properties.merge(
          "image_analysis_status" => "completed",
          "ai_analysis" => {
            "labels" => %w[document brand],
            "colors" => [],
            "quality_score" => 78,
            "suggested_tags" => %w[approved archive],
            "description" => "Brand overview document.",
            "similar_assets" => [],
          },
        )
      )

      post "/api/v1/assets/#{asset.id}/ai_analysis"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include(
        "status" => "completed",
        "quality_score" => 78,
        "description" => "Brand overview document."
      )
    end
  end
end
