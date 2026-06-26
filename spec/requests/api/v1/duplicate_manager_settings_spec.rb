require "swagger_helper"

RSpec.describe "Duplicate Manager Settings API", type: :request do
  let!(:admin)     { create(:user, :admin) }
  let!(:non_admin) { create(:user) }

  before { Setting.set("duplicate_manager_enabled", false) }

  # ---------------------------------------------------------------------------
  # GET /api/v1/duplicate_manager_settings
  # ---------------------------------------------------------------------------
  path "/api/v1/duplicate_manager_settings" do
    get "Fetch Duplicate Manager settings" do
      tags     "Duplicate Manager"
      produces "application/json"
      description "Returns current duplicate detection configuration plus scan status."

      response "200", "Settings returned (includes scan_status, scan_progress, last_scan_at)" do
        schema type: :object,
               properties: {
                 enabled:             { type: :boolean },
                 inbox_notifications: { type: :boolean },
                 max_display_groups:  { type: :integer },
                 scan_status:         { type: :string },
                 scan_progress:       { type: :object },
                 last_scan_at:        { type: :string, nullable: true },
               }

        before { sign_in admin }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to have_key("enabled")
          expect(data).to have_key("scan_status")
          expect(data).to have_key("scan_progress")
          expect(data).to have_key("last_scan_at")
          expect(data["max_display_groups"]).to eq(DuplicateGroup::DISPLAY_LIMIT)
        end
      end

      response "401", "Unauthenticated" do
        run_test!
      end
    end

    patch "Update Duplicate Manager settings" do
      tags     "Duplicate Manager"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          enabled:              { type: :boolean },
          inbox_notifications:  { type: :boolean },
        },
      }

      response "200", "Settings updated by admin" do
        let(:body) { { enabled: false, inbox_notifications: false } }

        before { sign_in admin }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["enabled"]).to be false
          expect(data["inbox_notifications"]).to be false
          expect(data["message"]).to be_present
        end
      end

      response "403", "Forbidden for non-admin" do
        let(:body) { { enabled: true } }

        before { sign_in non_admin }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["error"]).to include("Administrator")
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/duplicate_manager_settings/scan_status
  # ---------------------------------------------------------------------------
  path "/api/v1/duplicate_manager_settings/scan_status" do
    get "Get live scan status" do
      tags     "Duplicate Manager"
      produces "application/json"
      description "Returns the current status and progress of the background repository scan."

      response "200", "Scan status returned" do
        schema type: :object,
               properties: {
                 scan_status:   { type: :string },
                 scan_progress: { type: :object },
                 last_scan_at:  { type: :string, nullable: true },
               }

        before do
          sign_in admin
          Setting.set("duplicate_manager_scan_status", "completed")
          Setting.set("duplicate_manager_last_scan_at", Time.current.iso8601)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["scan_status"]).to eq("completed")
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # POST /api/v1/duplicate_manager_settings/trigger_scan
  # ---------------------------------------------------------------------------
  path "/api/v1/duplicate_manager_settings/trigger_scan" do
    post "Trigger a full repository scan" do
      tags     "Duplicate Manager"
      produces "application/json"
      description "Admin-only: queues a full repository scan for duplicates."

      response "200", "Scan queued" do
        before do
          sign_in admin
          Setting.set("duplicate_manager_enabled", true)
          Setting.set("duplicate_manager_scan_status", "idle")
          allow(DuplicateRepositoryScanWorker).to receive(:perform_async)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["status"]).to eq("queued")
          expect(DuplicateRepositoryScanWorker).to have_received(:perform_async)
        end
      end

      response "422", "Detection not enabled" do
        before do
          sign_in admin
          Setting.set("duplicate_manager_enabled", false)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["error"]).to include("Enable duplicate detection")
        end
      end

      response "422", "Scan already running" do
        before do
          sign_in admin
          Setting.set("duplicate_manager_enabled", true)
          Setting.set("duplicate_manager_scan_status", "running")
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["error"]).to include("already")
        end
      end

      response "403", "Forbidden for non-admin" do
        before { sign_in non_admin }
        run_test!
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Auto-trigger scan when enabling
  # ---------------------------------------------------------------------------
  describe "auto-trigger on enable" do
    before { sign_in admin }

    it "enqueues a scan when enabling detection" do
      allow(DuplicateRepositoryScanWorker).to receive(:perform_async)

      patch "/api/v1/duplicate_manager_settings",
            params:  { enabled: true }.to_json,
            headers: { "Content-Type" => "application/json" }

      expect(DuplicateRepositoryScanWorker).to have_received(:perform_async)
      data = JSON.parse(response.body)
      expect(data["scan_queued"]).to be true
    end

    it "does NOT enqueue a scan when detection was already enabled" do
      Setting.set("duplicate_manager_enabled", true)
      allow(DuplicateRepositoryScanWorker).to receive(:perform_async)

      patch "/api/v1/duplicate_manager_settings",
            params:  { inbox_notifications: false }.to_json,
            headers: { "Content-Type" => "application/json" }

      expect(DuplicateRepositoryScanWorker).not_to have_received(:perform_async)
    end

    it "does NOT enqueue when disabling" do
      Setting.set("duplicate_manager_enabled", true)
      allow(DuplicateRepositoryScanWorker).to receive(:perform_async)

      patch "/api/v1/duplicate_manager_settings",
            params:  { enabled: false }.to_json,
            headers: { "Content-Type" => "application/json" }

      expect(DuplicateRepositoryScanWorker).not_to have_received(:perform_async)
    end
  end

  # ---------------------------------------------------------------------------
  # Settings persistence
  # ---------------------------------------------------------------------------
  describe "settings persistence" do
    before { sign_in admin }

    it "persists the enabled flag across requests" do
      patch "/api/v1/duplicate_manager_settings",
            params:  { enabled: false }.to_json,
            headers: { "Content-Type" => "application/json" }

      get "/api/v1/duplicate_manager_settings"
      data = JSON.parse(response.body)
      expect(data["enabled"]).to be false
    end

    it "persists inbox_notifications across requests" do
      patch "/api/v1/duplicate_manager_settings",
            params:  { inbox_notifications: false }.to_json,
            headers: { "Content-Type" => "application/json" }

      get "/api/v1/duplicate_manager_settings"
      data = JSON.parse(response.body)
      expect(data["inbox_notifications"]).to be false
    end

    it "returns scan_status in GET response" do
      Setting.set("duplicate_manager_scan_status", "completed")

      get "/api/v1/duplicate_manager_settings"
      data = JSON.parse(response.body)
      expect(data["scan_status"]).to eq("completed")
    end
  end
end
