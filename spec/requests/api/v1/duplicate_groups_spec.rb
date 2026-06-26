require "swagger_helper"

RSpec.describe "Duplicate Groups API", type: :request do
  let!(:admin) { create(:user, :admin) }
  let!(:user)  { create(:user) }

  let(:valid_headers) { { "Content-Type" => "application/json" } }

  before { sign_in admin }

  # ---------------------------------------------------------------------------
  # GET /api/v1/duplicate_groups
  # ---------------------------------------------------------------------------
  path "/api/v1/duplicate_groups" do
    get "List duplicate groups" do
      tags        "Duplicate Manager"
      produces    "application/json"
      description "Returns duplicate groups (max 100). Filter by status with ?status=pending|resolved|dismissed|all."
      parameter name: :status, in: :query, type: :string, required: false,
                description: "pending (default), resolved, dismissed, all"

      response "200", "Groups listed" do
        schema type: :object,
               properties: {
                 total:  { type: :integer },
                 groups: { type: :array, items: { type: :object } },
               }

        let!(:pending_group)  { create(:duplicate_group, status: "pending") }
        let!(:resolved_group) { create(:duplicate_group, :resolved) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["total"]).to eq(1) # only pending by default
        end
      end

      response "200", "Returns all groups when status=all" do
        let!(:pending_group)  { create(:duplicate_group, status: "pending") }
        let!(:resolved_group) { create(:duplicate_group, :resolved) }
        let(:status) { "all" }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["total"]).to eq(2)
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/duplicate_groups/stats
  # ---------------------------------------------------------------------------
  path "/api/v1/duplicate_groups/stats" do
    get "Duplicate group statistics" do
      tags     "Duplicate Manager"
      produces "application/json"

      response "200", "Stats returned" do
        schema type: :object,
               properties: {
                 pending:   { type: :integer },
                 resolved:  { type: :integer },
                 dismissed: { type: :integer },
                 total:     { type: :integer },
               }

        before do
          create(:duplicate_group, status: "pending")
          create(:duplicate_group, :resolved)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["pending"]).to  eq(1)
          expect(data["resolved"]).to eq(1)
          expect(data["total"]).to    eq(2)
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/duplicate_groups/:id
  # ---------------------------------------------------------------------------
  path "/api/v1/duplicate_groups/{id}" do
    parameter name: :id, in: :path, type: :string, required: true

    get "Show a duplicate group" do
      tags     "Duplicate Manager"
      produces "application/json"

      response "200", "Group returned with assets" do
        let(:group) { create(:duplicate_group, status: "pending") }
        let(:id)    { group.id }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["group"]["id"]).to eq(group.id)
        end
      end

      response "404", "Group not found" do
        let(:id) { "non-existent-uuid" }
        run_test!
      end
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH /api/v1/duplicate_groups/:id/resolve
  # ---------------------------------------------------------------------------
  path "/api/v1/duplicate_groups/{id}/resolve" do
    parameter name: :id, in: :path, type: :string, required: true

    patch "Resolve a duplicate group" do
      tags        "Duplicate Manager"
      consumes    "application/json"
      produces    "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          action_type:         { type: :string, enum: %w[kept_all deleted_duplicates] },
          asset_ids_to_delete: { type: :array, items: { type: :string } },
        },
        required: [ "action_type" ],
      }

      response "200", "Group resolved (kept_all)" do
        let(:group) { create(:duplicate_group, status: "pending") }
        let(:id)    { group.id }
        let(:body)  { { action_type: "kept_all" } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["group"]["status"]).to eq("resolved")
          expect(data["group"]["resolution_action"]).to eq("kept_all")
        end
      end

      response "200", "Group resolved (deleted_duplicates)" do
        let!(:asset_to_delete) { create(:asset) }
        let!(:original_asset)  { create(:asset) }
        let!(:group) {
          g = create(:duplicate_group, status: "pending")
          create(:duplicate_group_asset, duplicate_group: g, asset: original_asset, is_original: true)
          create(:duplicate_group_asset, duplicate_group: g, asset: asset_to_delete, is_original: false)
          g
        }
        let(:id)   { group.id }
        let(:body) { { action_type: "deleted_duplicates", asset_ids_to_delete: [ asset_to_delete.id ] } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["deleted_ids"]).to include(asset_to_delete.id)
          expect(asset_to_delete.reload.deleted_at).not_to be_nil
        end
      end

      response "422", "Invalid action" do
        let(:group) { create(:duplicate_group, status: "pending") }
        let(:id)    { group.id }
        let(:body)  { { action_type: "invalid_action" } }
        run_test!
      end

      response "404", "Group not found" do
        let(:id)   { "non-existent-uuid" }
        let(:body) { { action_type: "kept_all" } }
        run_test!
      end
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH /api/v1/duplicate_groups/:id/dismiss
  # ---------------------------------------------------------------------------
  path "/api/v1/duplicate_groups/{id}/dismiss" do
    parameter name: :id, in: :path, type: :string, required: true

    patch "Dismiss a duplicate group" do
      tags     "Duplicate Manager"
      produces "application/json"

      response "200", "Group dismissed" do
        let(:group) { create(:duplicate_group, status: "pending") }
        let(:id)    { group.id }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["group"]["status"]).to eq("dismissed")
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH /api/v1/duplicate_groups/bulk_resolve
  # ---------------------------------------------------------------------------
  path "/api/v1/duplicate_groups/bulk_resolve" do
    patch "Bulk-resolve duplicate groups" do
      tags     "Duplicate Manager"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          group_ids: { type: :array, items: { type: :string } },
        },
        required: [ "group_ids" ],
      }

      response "200", "Groups resolved" do
        let!(:group1) { create(:duplicate_group, status: "pending") }
        let!(:group2) { create(:duplicate_group, status: "pending") }
        let(:body)    { { group_ids: [ group1.id, group2.id ] } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["resolved_count"]).to eq(2)
          expect(group1.reload.status).to eq("resolved")
          expect(group2.reload.status).to eq("resolved")
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Auth guard
  # ---------------------------------------------------------------------------
  describe "unauthenticated access" do
    before { sign_out admin }

    it "returns 401 for index" do
      get "/api/v1/duplicate_groups"
      expect(response).to have_http_status(:unauthorized).or have_http_status(:redirect)
    end
  end
end
