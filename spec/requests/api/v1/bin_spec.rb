require "swagger_helper"

RSpec.describe "Bin API", type: :request do
  let!(:admin)     { create(:user, :admin) }
  let!(:non_admin) { create(:user) }

  let!(:trashed_asset)  { create(:asset, :trashed, title: "Old Campaign Banner",  properties: { "content_type" => "image/jpeg", "size" => 102_400 }) }
  let!(:trashed_asset2) { create(:asset, :trashed, title: "Quarterly Report PDF", properties: { "content_type" => "application/pdf", "size" => 512_000 }) }
  let!(:trashed_folder) { create(:folder, deleted_at: 1.day.ago, name: "Archive 2024") }
  let!(:active_asset)   { create(:asset, title: "Active Asset") }

  # ===========================================================================
  # GET /api/v1/bin
  # ===========================================================================
  path "/api/v1/bin" do
    get "List all soft-deleted items" do
      tags        "Bin"
      produces    "application/json"
      description "Returns all trashed assets and folders with filtering, sorting, and pagination."

      parameter name: :q,         in: :query, type: :string,  required: false, description: "Name/title search"
      parameter name: :type,      in: :query, type: :string,  required: false, description: "all | asset | folder | image | video | document"
      parameter name: :sort,      in: :query, type: :string,  required: false, description: "deleted_at | name | size"
      parameter name: :direction, in: :query, type: :string,  required: false, description: "asc | desc"
      parameter name: :page,      in: :query, type: :integer, required: false
      parameter name: :per_page,  in: :query, type: :integer, required: false

      response "200", "Returns paginated bin contents" do
        schema type: :object,
               properties: {
                 items:          { type: :array,   items: { type: :object } },
                 pagination:     { type: :object },
                 retention_days: { type: :integer },
               }

        before { sign_in admin }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to have_key("items")
          expect(data).to have_key("pagination")
          expect(data["retention_days"]).to eq(30)
          # Only trashed items — not active_asset
          names = data["items"].map { |i| i["name"] }
          expect(names).to include("Old Campaign Banner", "Quarterly Report PDF", "Archive 2024")
          expect(names).not_to include("Active Asset")
        end
      end
    end
  end

  describe "GET /api/v1/bin — filters" do
    before { sign_in admin }

    it "filters by search query" do
      get "/api/v1/bin", params: { q: "Campaign" }
      data = JSON.parse(response.body)
      expect(data["items"].map { |i| i["name"] }).to include("Old Campaign Banner")
      expect(data["items"].map { |i| i["name"] }).not_to include("Quarterly Report PDF")
    end

    it "filters by type=folder" do
      get "/api/v1/bin", params: { type: "folder" }
      data = JSON.parse(response.body)
      types = data["items"].map { |i| i["item_type"] }.uniq
      expect(types).to eq([ "folder" ])
    end

    it "filters by type=asset" do
      get "/api/v1/bin", params: { type: "asset" }
      data = JSON.parse(response.body)
      types = data["items"].map { |i| i["item_type"] }.uniq
      expect(types).to eq([ "asset" ])
    end

    it "filters by type=image" do
      get "/api/v1/bin", params: { type: "image" }
      data = JSON.parse(response.body)
      expect(data["items"].map { |i| i["name"] }).to include("Old Campaign Banner")
      expect(data["items"].map { |i| i["name"] }).not_to include("Quarterly Report PDF")
    end

    it "paginates results" do
      get "/api/v1/bin", params: { per_page: 1, page: 1 }
      data = JSON.parse(response.body)
      expect(data["items"].length).to eq(1)
      expect(data["pagination"]["total"]).to eq(3)
      expect(data["pagination"]["pages"]).to eq(3)
    end

    it "sorts by name ascending" do
      get "/api/v1/bin", params: { sort: "name", direction: "asc" }
      data  = JSON.parse(response.body)
      names = data["items"].map { |i| i["name"] }
      expect(names).to eq(names.sort_by(&:downcase))
    end

    it "ignores invalid sort fields (uses default)" do
      get "/api/v1/bin", params: { sort: "injected_column; DROP TABLE assets;--", direction: "asc" }
      expect(response).to have_http_status(:ok)
    end
  end

  # ===========================================================================
  # GET /api/v1/bin/stats
  # ===========================================================================
  path "/api/v1/bin/stats" do
    get "Aggregate bin statistics" do
      tags        "Bin"
      produces    "application/json"
      description "Returns counts, storage usage, and retention policy for the bin."

      response "200", "Statistics returned" do
        schema type: :object,
               properties: {
                 total_items:       { type: :integer },
                 total_assets:      { type: :integer },
                 total_folders:     { type: :integer },
                 total_size_bytes:  { type: :integer },
                 retention_days:    { type: :integer },
                 oldest_deleted_at: { type: :string, nullable: true },
               }

        before { sign_in admin }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["total_items"]).to  eq(3)
          expect(data["total_assets"]).to eq(2)
          expect(data["total_folders"]).to eq(1)
          expect(data["total_size_bytes"]).to be_a(Integer)
          expect(data["retention_days"]).to eq(30)
        end
      end
    end
  end

  # ===========================================================================
  # POST /api/v1/bin/bulk_restore
  # ===========================================================================
  path "/api/v1/bin/bulk_restore" do
    post "Bulk restore items from bin" do
      tags        "Bin"
      consumes    "application/json"
      produces    "application/json"
      description "Restores one or more soft-deleted assets or folders."

      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          items: {
            type: :array,
            items: {
              type: :object,
              properties: {
                id:   { type: :integer },
                type: { type: :string },
              },
            },
          },
        },
      }

      response "200", "Items restored" do
        let(:body) { { items: [ { id: trashed_asset.id, type: "asset" } ] } }

        before { sign_in admin }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["restored"]).to eq(1)
          expect(data["errors"]).to be_empty
          expect(trashed_asset.reload.deleted_at).to be_nil
        end
      end
    end
  end

  describe "POST /api/v1/bin/bulk_restore" do
    before { sign_in admin }

    it "restores multiple items at once" do
      post "/api/v1/bin/bulk_restore", params: {
        items: [
          { id: trashed_asset.id,  type: "asset"  },
          { id: trashed_folder.id, type: "folder" },
        ],
      }, as: :json
      data = JSON.parse(response.body)
      expect(data["restored"]).to eq(2)
      expect(trashed_asset.reload.deleted_at).to be_nil
      expect(trashed_folder.reload.deleted_at).to be_nil
    end

    it "returns an error for items not in the bin" do
      post "/api/v1/bin/bulk_restore", params: {
        items: [ { id: active_asset.id, type: "asset" } ],
      }, as: :json
      data = JSON.parse(response.body)
      expect(data["errors"]).not_to be_empty
    end

    it "requires authentication" do
      sign_out admin
      post "/api/v1/bin/bulk_restore", params: { items: [] }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # DELETE /api/v1/bin/bulk_destroy
  # ===========================================================================
  describe "DELETE /api/v1/bin/bulk_destroy" do
    before { sign_in admin }

    it "permanently deletes multiple items" do
      delete "/api/v1/bin/bulk_destroy", params: {
        items: [
          { id: trashed_asset.id,  type: "asset"  },
          { id: trashed_folder.id, type: "folder" },
        ],
      }, as: :json
      data = JSON.parse(response.body)
      expect(data["deleted"]).to eq(2)
      expect { trashed_asset.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect { trashed_folder.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "returns errors for items not in the bin" do
      delete "/api/v1/bin/bulk_destroy", params: {
        items: [ { id: active_asset.id, type: "asset" } ],
      }, as: :json
      data = JSON.parse(response.body)
      expect(data["errors"]).not_to be_empty
    end

    it "requires authentication" do
      sign_out admin
      delete "/api/v1/bin/bulk_destroy", params: { items: [] }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # DELETE /api/v1/bin/empty
  # ===========================================================================
  path "/api/v1/bin/empty" do
    delete "Empty the entire bin" do
      tags        "Bin"
      produces    "application/json"
      description "Permanently destroys every item in the bin (admin only)."

      response "200", "Bin emptied" do
        schema type: :object,
               properties: {
                 deleted: { type: :integer },
                 message: { type: :string },
               }

        before { sign_in admin }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["deleted"]).to be >= 2
          expect(Asset.trashed.count).to  eq(0)
          expect(Folder.trashed.count).to eq(0)
        end
      end
    end
  end

  describe "DELETE /api/v1/bin/empty" do
    before { sign_in admin }

    it "empties the entire bin" do
      delete "/api/v1/bin/empty"
      data = JSON.parse(response.body)
      expect(data["deleted"]).to be >= 2
      expect(Asset.trashed.count).to eq(0)
      expect(Folder.trashed.count).to eq(0)
    end

    it "does not affect active assets" do
      delete "/api/v1/bin/empty"
      expect(active_asset.reload).to be_present
    end

    it "requires authentication" do
      sign_out admin
      delete "/api/v1/bin/empty"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # Serialisation checks
  # ===========================================================================
  describe "item serialisation" do
    before { sign_in admin }

    it "includes required fields for assets" do
      get "/api/v1/bin", params: { type: "asset" }
      item = JSON.parse(response.body)["items"].find { |i| i["id"] == trashed_asset.id }

      expect(item).to include(
        "id", "grid_id", "item_type", "name", "media_type",
        "deleted_at", "expires_at", "size_bytes", "size_human",
        "content_type", "url"
      )
      expect(item["item_type"]).to eq("asset")
      expect(item["grid_id"]).to eq("asset_#{trashed_asset.id}")
      expect(item["media_type"]).to eq("image")
    end

    it "includes required fields for folders" do
      get "/api/v1/bin", params: { type: "folder" }
      item = JSON.parse(response.body)["items"].find { |i| i["id"] == trashed_folder.id }

      expect(item).to include("id", "grid_id", "item_type", "name", "deleted_at", "expires_at")
      expect(item["item_type"]).to eq("folder")
      expect(item["grid_id"]).to eq("folder_#{trashed_folder.id}")
    end

    it "calculates expires_at 30 days after deleted_at" do
      get "/api/v1/bin"
      item = JSON.parse(response.body)["items"].find { |i| i["id"] == trashed_asset.id && i["item_type"] == "asset" }
      deleted  = Time.parse(item["deleted_at"])
      expires  = Time.parse(item["expires_at"])
      expect(expires).to be_within(1.second).of(deleted + 30.days)
    end
  end

  # ===========================================================================
  # GET /api/v1/bin/retention_policy
  # ===========================================================================
  path "/api/v1/bin/retention_policy" do
    get "Fetch current retention policy" do
      tags        "Bin"
      produces    "application/json"
      description "Returns the current automatic purge policy."

      response "200", "Policy returned" do
        schema type: :object,
               properties: {
                 retention_days:    { type: :integer },
                 workflow_behavior: { type: :string  },
                 batch_size:        { type: :integer },
                 notify_admins:     { type: :boolean },
               }

        before { sign_in admin }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["retention_days"]).to    eq(BinPurgeWorker::DEFAULT_RETENTION_DAYS)
          expect(data["workflow_behavior"]).to eq(BinPurgeWorker::DEFAULT_WORKFLOW_BEHAVIOR)
          expect(data["batch_size"]).to eq(BinPurgeWorker::DEFAULT_BATCH_SIZE)
          expect(data).to have_key("notify_admins")
          expect(data).to have_key("next_scheduled_at")
        end
      end
    end

    put "Update retention policy (admin only)" do
      tags        "Bin"
      consumes    "application/json"
      produces    "application/json"
      description "Updates the retention policy. Admin only."

      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          retention_days:    { type: :integer },
          workflow_behavior: { type: :string  },
          batch_size:        { type: :integer },
          notify_admins:     { type: :boolean },
        },
      }

      response "200", "Policy updated" do
        let(:body) { { retention_days: 14, workflow_behavior: "force_terminate" } }

        before { sign_in admin }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["retention_days"]).to    eq(14)
          expect(data["workflow_behavior"]).to eq("force_terminate")
          expect(Setting.get("bin_retention_days").to_i).to eq(14)
        end
      end

      response "403", "Non-admin rejected" do
        let(:body) { { retention_days: 7 } }
        before { sign_in non_admin }
        run_test! do |response|
          expect(response.status).to eq(403)
        end
      end
    end
  end

  describe "PUT /api/v1/bin/retention_policy" do
    before { sign_in admin }

    it "clamps retention_days to valid range" do
      put "/api/v1/bin/retention_policy", params: { retention_days: 500 }, as: :json
      expect(JSON.parse(response.body)["retention_days"]).to eq(365)

      put "/api/v1/bin/retention_policy", params: { retention_days: 0 }, as: :json
      # 0 is not a valid value; should be ignored or clamped to 1
      data = JSON.parse(response.body)
      expect(data["retention_days"]).to be >= 1
    end

    it "rejects invalid workflow_behavior values" do
      put "/api/v1/bin/retention_policy", params: { workflow_behavior: "delete_everything" }, as: :json
      # Should not change the setting
      current = JSON.parse(response.body)["workflow_behavior"]
      expect(current).not_to eq("delete_everything")
    end

    it "toggles notify_admins" do
      put "/api/v1/bin/retention_policy", params: { notify_admins: false }, as: :json
      expect(JSON.parse(response.body)["notify_admins"]).to be false
    end
  end

  # ===========================================================================
  # POST /api/v1/bin/trigger_purge
  # ===========================================================================
  path "/api/v1/bin/trigger_purge" do
    post "Manually trigger a bin purge (admin only)" do
      tags        "Bin"
      produces    "application/json"
      description "Enqueues BinPurgeWorker. Returns 409 when already running."

      response "200", "Purge queued" do
        before { sign_in admin }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["queued"]).to be true
        end
      end

      response "409", "Already running" do
        before do
          sign_in admin
          Setting.set(BinPurgeWorker::LOCK_KEY, "running")
        end

        run_test! do |response|
          expect(response.status).to eq(409)
        end
      end

      response "403", "Non-admin rejected" do
        before { sign_in non_admin }
        run_test! do |response|
          expect(response.status).to eq(403)
        end
      end
    end
  end

  describe "POST /api/v1/bin/trigger_purge" do
    before { sign_in admin }

    it "enqueues BinPurgeWorker" do
      expect(BinPurgeWorker).to receive(:perform_async)
      post "/api/v1/bin/trigger_purge"
    end

    it "sets status to queued" do
      allow(BinPurgeWorker).to receive(:perform_async)
      post "/api/v1/bin/trigger_purge"
      expect(Setting.get(BinPurgeWorker::LOCK_KEY)).to eq("queued")
    end

    it "records who triggered the purge" do
      allow(BinPurgeWorker).to receive(:perform_async)
      post "/api/v1/bin/trigger_purge"

      triggered = Setting.get("bin_purge_triggered_by")
      expect(triggered).to be_a(Hash)
      expect(triggered[:user_id] || triggered["user_id"]).to eq(admin.id)
      expect(triggered[:source]  || triggered["source"]).to  eq("manual")
    end

    it "returns the triggering user's name in the response" do
      allow(BinPurgeWorker).to receive(:perform_async)
      post "/api/v1/bin/trigger_purge"
      expect(JSON.parse(response.body)["triggered_by"]).to eq(admin.name)
    end

    it "returns 409 when purge is already running" do
      Setting.set(BinPurgeWorker::LOCK_KEY, "running")
      post "/api/v1/bin/trigger_purge"
      expect(response).to have_http_status(:conflict)
    end

    it "returns 409 when purge is already queued" do
      Setting.set(BinPurgeWorker::LOCK_KEY, "queued")
      post "/api/v1/bin/trigger_purge"
      expect(response).to have_http_status(:conflict)
    end

    it "rejects non-admins with 403" do
      sign_out admin
      sign_in non_admin
      post "/api/v1/bin/trigger_purge"
      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      sign_out admin
      post "/api/v1/bin/trigger_purge"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # GET /api/v1/bin/purge_status
  # ===========================================================================
  path "/api/v1/bin/purge_status" do
    get "Get current purge status" do
      tags        "Bin"
      produces    "application/json"
      description "Returns the current purge job status and last run results."

      response "200", "Status returned" do
        schema type: :object,
               properties: {
                 status:       { type: :string },
                 last_ran_at:  { type: :string, nullable: true },
                 last_results: { type: :object },
                 policy:       { type: :object },
               }

        before { sign_in admin }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to have_key("status")
          expect(data).to have_key("last_results")
          expect(data).to have_key("policy")
        end
      end
    end
  end

  describe "GET /api/v1/bin/purge_status" do
    before { sign_in admin }

    it "returns idle when no purge has run" do
      get "/api/v1/bin/purge_status"
      data = JSON.parse(response.body)
      expect(data["status"]).to eq("idle")
      expect(data["last_results"]).to eq({})
    end

    it "reflects current running status" do
      Setting.set(BinPurgeWorker::LOCK_KEY, "running")
      get "/api/v1/bin/purge_status"
      expect(JSON.parse(response.body)["status"]).to eq("running")
    end

    it "includes policy details" do
      get "/api/v1/bin/purge_status"
      data = JSON.parse(response.body)
      expect(data["policy"]).to include("retention_days", "workflow_behavior")
    end

    it "includes triggered_by once a purge is triggered" do
      allow(BinPurgeWorker).to receive(:perform_async)
      post "/api/v1/bin/trigger_purge"

      get "/api/v1/bin/purge_status"
      data = JSON.parse(response.body)
      expect(data["triggered_by"]).to include("user_name" => admin.name, "source" => "manual")
    end

    it "requires authentication" do
      sign_out admin
      get "/api/v1/bin/purge_status"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # GET /api/v1/bin/ai/smart_suggestions
  # ===========================================================================
  describe "GET /api/v1/bin/ai/smart_suggestions" do
    let!(:old_asset) do
      create(:asset, :trashed, deleted_at: 40.days.ago,
             title: "Stale Banner", properties: { "content_type" => "image/jpeg", "size" => 250_000 })
    end
    let!(:recent_asset) do
      create(:asset, :trashed, deleted_at: 5.days.ago, title: "Recent Doc")
    end

    before { sign_in admin }

    it "returns AI suggestion stubs for expired assets" do
      get "/api/v1/bin/ai/smart_suggestions"
      data = JSON.parse(response.body)

      expect(data).to have_key("suggestions")
      expect(data["ai_available"]).to be false
      expect(data["gateway_url"]).to include("capri-dam-ai-gateway")

      ids = data["suggestions"].map { |s| s["id"] }
      expect(ids).to include(old_asset.id)
      # Recent asset is within retention window — not suggested
      expect(ids).not_to include(recent_asset.id)
    end

    it "includes heuristic_score and AI-ready null fields" do
      get "/api/v1/bin/ai/smart_suggestions"
      suggestion = JSON.parse(response.body)["suggestions"].first

      expect(suggestion).to include("heuristic_score", "ai_risk_score", "ai_reason", "ai_tags")
      expect(suggestion["heuristic_score"]).to be_a(Integer)
      expect(suggestion["ai_risk_score"]).to be_nil
    end

    it "excludes assets with active workflows" do
      wf_asset = create(:asset, :trashed, deleted_at: 50.days.ago, title: "In Review")
      create(:workflow_instance, asset: wf_asset, status: "in_review")

      get "/api/v1/bin/ai/smart_suggestions"
      ids = JSON.parse(response.body)["suggestions"].map { |s| s["id"] }
      expect(ids).not_to include(wf_asset.id)
    end

    it "respects the limit param" do
      get "/api/v1/bin/ai/smart_suggestions", params: { limit: 1 }
      expect(JSON.parse(response.body)["suggestions"].length).to be <= 1
    end

    it "rejects non-admins with 403" do
      sign_out admin
      sign_in non_admin
      get "/api/v1/bin/ai/smart_suggestions"
      expect(response).to have_http_status(:forbidden)
    end
  end

  # ===========================================================================
  # GET /api/v1/bin/ai/cleanup_report
  # ===========================================================================
  describe "GET /api/v1/bin/ai/cleanup_report" do
    before { sign_in admin }

    it "returns a structured cleanup report stub" do
      get "/api/v1/bin/ai/cleanup_report"
      data = JSON.parse(response.body)

      expect(data["ai_available"]).to be false
      expect(data["report"]).to include("summary", "items_deleted", "next_actions")
      expect(data["report"]["next_actions"]).to be_an(Array)
    end

    it "reflects last purge results in the report" do
      Setting.set("bin_purge_last_results", { "deleted" => 7, "skipped" => 2 })
      get "/api/v1/bin/ai/cleanup_report"
      data = JSON.parse(response.body)
      expect(data["report"]["items_deleted"]).to eq(7)
      expect(data["report"]["items_skipped"]).to eq(2)
    end

    it "rejects non-admins with 403" do
      sign_out admin
      sign_in non_admin
      get "/api/v1/bin/ai/cleanup_report"
      expect(response).to have_http_status(:forbidden)
    end
  end
end
