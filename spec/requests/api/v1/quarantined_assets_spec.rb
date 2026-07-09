require "swagger_helper"

RSpec.describe "Quarantined Assets API", type: :request do
  let!(:admin) { create(:user, :admin) }
  let!(:user) { create(:user) }

  def json_body
    JSON.parse(response.body)
  end

  def build_payload(filename:, owner_id:, content_type: "image/png", uploaded_at: "2026-07-08T10:00:00Z")
    {
      "asset" => {
        "name" => filename,
        "user_id" => owner_id,
        "uploaded_at" => uploaded_at,
        "properties" => {
          "content_type" => content_type,
          "size" => 2048,
        },
      },
    }
  end

  before { sign_in admin }

  path "/api/v1/quarantined_assets" do
    get "List quarantined assets" do
      tags "Quarantine"
      produces "application/json"
      description "Returns quarantined assets filtered by status with pagination."

      parameter name: :status, in: :query, type: :string, required: false,
                description: "pending_review (default), resolved, discarded, all"
      parameter name: :page, in: :query, type: :integer, required: false
      parameter name: :per_page, in: :query, type: :integer, required: false

      response "200", "Quarantined assets listed" do
        schema type: :object,
               properties: {
                 items: { type: :array, items: { type: :object } },
                 pagination: { type: :object },
               }

        let!(:pending_entry) do
          create(
            :quarantined_asset,
            original_payload: build_payload(filename: "flagged.png", owner_id: user.id),
            status: "pending_review"
          )
        end
        let!(:resolved_entry) { create(:quarantined_asset, status: "resolved") }

        run_test! do |_response|
          expect(json_body["items"].map { |item| item["id"] }).to eq([ pending_entry.id ])
          expect(json_body["pagination"]["total"]).to eq(1)
        end
      end

      response "200", "Returns all quarantined assets when status=all" do
        let!(:pending_entry) { create(:quarantined_asset, status: "pending_review") }
        let!(:resolved_entry) { create(:quarantined_asset, status: "resolved") }
        let(:status) { "all" }

        run_test! do |_response|
          expect(json_body["pagination"]["total"]).to eq(2)
          expect(json_body["items"].map { |item| item["status"] }).to include("pending_review", "resolved")
        end
      end
    end
  end

  path "/api/v1/quarantined_assets/stats" do
    get "Quarantine statistics" do
      tags "Quarantine"
      produces "application/json"

      response "200", "Quarantine stats returned" do
        schema type: :object,
               properties: {
                 pending_review: { type: :integer },
                 resolved: { type: :integer },
                 discarded: { type: :integer },
                 total: { type: :integer },
               }

        before do
          create(:quarantined_asset, status: "pending_review")
          create(:quarantined_asset, status: "resolved")
          create(:quarantined_asset, status: "discarded")
        end

        run_test! do |_response|
          expect(json_body).to include(
            "pending_review" => 1,
            "resolved" => 1,
            "discarded" => 1,
            "total" => 3
          )
        end
      end
    end
  end

  path "/api/v1/quarantined_assets/{id}" do
    parameter name: :id, in: :path, type: :integer, required: true

    get "Show a quarantined asset" do
      tags "Quarantine"
      produces "application/json"

      response "200", "Quarantined asset returned" do
        let!(:entry) do
          create(
            :quarantined_asset,
            original_payload: build_payload(filename: "blocked.mov", owner_id: user.id, content_type: "video/mp4")
          )
        end
        let(:id) { entry.id }

        run_test! do |_response|
          expect(json_body["entry"]["asset"]["title"]).to eq("blocked.mov")
          expect(json_body["entry"]["asset"]["content_type"]).to eq("video/mp4")
          expect(json_body["entry"]["original_payload"]).to be_present
        end
      end

      response "404", "Quarantined asset not found" do
        let(:id) { 999_999 }
        run_test!
      end
    end
  end

  path "/api/v1/quarantined_assets/{id}/release" do
    parameter name: :id, in: :path, type: :integer, required: true

    patch "Release a quarantined asset" do
      tags "Quarantine"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          review_notes: { type: :string },
        },
      }

      response "200", "Quarantined asset released" do
        let!(:asset) do
          create(
            :asset,
            user: user,
            title: "Rejected hero",
            status: "rejected",
            deleted_at: 2.hours.ago,
            properties: { "content_type" => "image/png", "storage_path" => "assets/rejected-hero.png" }
          )
        end
        let!(:entry) { create(:quarantined_asset, asset: asset, status: "pending_review") }
        let(:id) { entry.id }
        let(:body) { { review_notes: "Release approved after manual review" } }

        run_test! do |_response|
          expect(entry.reload.status).to eq("resolved")
          expect(entry.reviewed_by).to eq(admin)
          expect(entry.review_notes).to eq("Release approved after manual review")
          expect(asset.reload.status).to eq("ready")
          expect(asset.deleted_at).to be_nil
        end
      end
    end
  end

  path "/api/v1/quarantined_assets/{id}/discard" do
    parameter name: :id, in: :path, type: :integer, required: true

    patch "Discard a quarantined asset" do
      tags "Quarantine"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          review_notes: { type: :string },
        },
      }

      response "200", "Quarantined asset discarded" do
        let!(:asset) do
          create(
            :asset,
            user: user,
            title: "Unsafe file",
            status: "ready",
            properties: { "content_type" => "application/pdf", "storage_path" => "assets/unsafe.pdf" }
          )
        end
        let!(:entry) { create(:quarantined_asset, asset: asset, status: "pending_review") }
        let(:id) { entry.id }
        let(:body) { { review_notes: "Discarded due to policy violation" } }

        run_test! do |_response|
          expect(entry.reload.status).to eq("discarded")
          expect(entry.reviewed_by).to eq(admin)
          expect(asset.reload).to be_trashed
          expect(asset.status).to eq("rejected")
        end
      end
    end
  end

  describe "GET /api/v1/quarantined_assets" do
    let!(:pending_entry) { create(:quarantined_asset, status: "pending_review") }
    let!(:resolved_entry) { create(:quarantined_asset, status: "resolved") }

    it "defaults to pending_review status" do
      get "/api/v1/quarantined_assets"

      expect(response).to have_http_status(:ok)
      expect(json_body["items"].map { |item| item["id"] }).to eq([ pending_entry.id ])
    end

    it "filters by status" do
      get "/api/v1/quarantined_assets", params: { status: "resolved" }

      expect(response).to have_http_status(:ok)
      expect(json_body["items"].map { |item| item["id"] }).to eq([ resolved_entry.id ])
    end
  end

  describe "GET /api/v1/quarantined_assets/:id" do
    let!(:entry) do
      create(
        :quarantined_asset,
        original_payload: build_payload(filename: "fallback.jpg", owner_id: user.id)
      )
    end

    it "serializes fallback asset details from the payload when no asset is linked" do
      get "/api/v1/quarantined_assets/#{entry.id}"

      expect(response).to have_http_status(:ok)
      expect(json_body.dig("entry", "asset", "title")).to eq("fallback.jpg")
      expect(json_body.dig("entry", "asset", "uploaded_by")).to eq(user.email)
    end
  end

  describe "PATCH /api/v1/quarantined_assets/:id/release" do
    let!(:entry) do
      create(
        :quarantined_asset,
        original_payload: build_payload(filename: "clean-now.png", owner_id: user.id),
        status: "pending_review",
        asset: nil
      )
    end

    it "creates a ready asset when the quarantine entry has no linked asset" do
      expect {
        patch "/api/v1/quarantined_assets/#{entry.id}/release",
              params: { review_notes: "Looks safe" },
              as: :json
      }.to change(Asset, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(entry.reload.asset).to be_present
      expect(entry.asset).to have_attributes(title: "clean-now.png", status: "ready")
    end
  end

  describe "authorization" do
    let!(:entry) { create(:quarantined_asset) }

    it "returns 403 for a non-admin user" do
      sign_out admin
      sign_in user

      get "/api/v1/quarantined_assets"

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 403 for release by a non-admin user" do
      sign_out admin
      sign_in user

      patch "/api/v1/quarantined_assets/#{entry.id}/release", as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 401 for unauthenticated access" do
      sign_out admin

      get "/api/v1/quarantined_assets"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
