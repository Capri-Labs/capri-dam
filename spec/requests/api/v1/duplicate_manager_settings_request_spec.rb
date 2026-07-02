# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::DuplicateManagerSettings coverage", type: :request do
  let(:admin) { create(:user, admin: true) }
  let(:user) { create(:user) }

  def json = response.parsed_body

  before do
    allow(DuplicateRepositoryScanWorker).to receive(:perform_async)
  end

  describe "GET /api/v1/duplicate_manager_settings" do
    it "requires authentication and returns defaults with non-hash scan progress coerced" do
      Setting.set("duplicate_manager_enabled", "true")
      Setting.set("duplicate_manager_inbox_notifications", nil)
      Setting.set("duplicate_manager_scan_status", nil)
      Setting.set("duplicate_manager_scan_progress", "not-a-hash")

      get "/api/v1/duplicate_manager_settings", as: :json
      expect(response).to have_http_status(:unauthorized)

      sign_in user
      get "/api/v1/duplicate_manager_settings", as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to include(
        "enabled" => true,
        "inbox_notifications" => true,
        "scan_status" => "idle",
        "scan_progress" => {},
        "max_display_groups" => DuplicateGroup::DISPLAY_LIMIT,
      )
    end
  end

  describe "PATCH /api/v1/duplicate_manager_settings" do
    it "forbids non-admin users" do
      sign_in user

      patch "/api/v1/duplicate_manager_settings", params: { enabled: true }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(json["error"]).to include("Administrator")
    end

    it "persists boolean-like strings and queues only first enable" do
      sign_in admin
      Setting.set("duplicate_manager_enabled", false)

      patch "/api/v1/duplicate_manager_settings", params: { enabled: "1", inbox_notifications: "false" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to include("enabled" => true, "inbox_notifications" => false, "scan_queued" => true)
      expect(Setting.get("duplicate_manager_scan_status")).to eq("queued")
      expect(DuplicateRepositoryScanWorker).to have_received(:perform_async).once

      patch "/api/v1/duplicate_manager_settings", params: { enabled: true }, as: :json
      expect(json["scan_queued"]).to be(false)
      expect(DuplicateRepositoryScanWorker).to have_received(:perform_async).once
    end

    it "renders worker errors as unprocessable entity" do
      sign_in admin
      Setting.set("duplicate_manager_enabled", false)
      allow(DuplicateRepositoryScanWorker).to receive(:perform_async).and_raise(StandardError, "sidekiq down")

      patch "/api/v1/duplicate_manager_settings", params: { enabled: true }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("sidekiq down")
    end
  end

  describe "scan status and trigger" do
    it "returns live hash progress" do
      sign_in user
      Setting.set("duplicate_manager_scan_status", "completed")
      Setting.set("duplicate_manager_scan_progress", { processed: 10 })
      Setting.set("duplicate_manager_last_scan_at", "2026-07-01T12:00:00Z")

      get "/api/v1/duplicate_manager_settings/scan_status", as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to include(
        "scan_status" => "completed",
        "scan_progress" => { "processed" => 10 },
        "last_scan_at" => "2026-07-01T12:00:00Z",
      )
    end

    it "handles disabled, already queued, success, forbidden, and enqueue errors" do
      sign_in admin
      Setting.set("duplicate_manager_enabled", false)

      post "/api/v1/duplicate_manager_settings/trigger_scan", as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to include("Enable duplicate detection")

      Setting.set("duplicate_manager_enabled", true)
      Setting.set("duplicate_manager_scan_status", "queued")
      post "/api/v1/duplicate_manager_settings/trigger_scan", as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json).to include("status" => "queued")

      Setting.set("duplicate_manager_scan_status", "idle")
      post "/api/v1/duplicate_manager_settings/trigger_scan", as: :json
      expect(response).to have_http_status(:ok)
      expect(json).to include("status" => "queued")

      allow(DuplicateRepositoryScanWorker).to receive(:perform_async).and_raise(StandardError, "queue unavailable")
      Setting.set("duplicate_manager_scan_status", "idle")
      post "/api/v1/duplicate_manager_settings/trigger_scan", as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("queue unavailable")

      sign_out admin
      sign_in user
      post "/api/v1/duplicate_manager_settings/trigger_scan", as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
