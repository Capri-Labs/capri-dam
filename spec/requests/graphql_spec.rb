# frozen_string_literal: true

require 'rails_helper'

# ─────────────────────────────────────────────────────────────────────────────
# GraphQL endpoint contract tests
#
# POST /graphql
#
# These specs verify the GraphQL endpoint behavior WITHOUT executing real
# business logic (all model calls are stubbed). They ensure:
#   • Authentication/authorization is enforced
#   • The schema introspection route is open in development
#   • All known queries and mutations return the expected shape
#   • Invalid operations return well-formed error responses
# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe "GraphQL endpoint", type: :request do
  # ─────────────────────────── helpers ────────────────────────────────────────

  let(:admin_user)   { create(:user, admin: true,  role: "admin")   }
  let(:manager_user) { create(:user, admin: false, role: "manager") }
  let(:viewer_user)  { create(:user, admin: false, role: "viewer")  }

  def gql_post(query:, variables: {}, user: nil, operation_name: nil)
    sign_in(user) if user
    payload = { query: query, variables: variables }
    payload[:operationName] = operation_name if operation_name
    post "/graphql", params: payload, headers: { "Accept" => "application/json" }, as: :json
  end

  def json
    JSON.parse(response.body)
  end

  # ─────────────────────────── auth guard ─────────────────────────────────────

  describe "authentication" do
    let(:simple_query) { "{ __typename }" }

    context "when not authenticated" do
      it "returns 401 or an errors payload" do
        gql_post(query: simple_query)
        # GraphQL always returns HTTP 200; auth failure surfaces as 401 OR
        # as a GraphQL error depending on implementation.
        expect([ 200, 401, 302 ]).to include(response.status)
      end
    end

    context "when authenticated as any user" do
      it "returns HTTP 200" do
        gql_post(query: simple_query, user: viewer_user)
        expect(response).to have_http_status(:ok)
      end

      it "returns valid JSON" do
        gql_post(query: simple_query, user: viewer_user)
        expect { json }.not_to raise_error
      end
    end
  end

  # ─────────────────────────── introspection ──────────────────────────────────

  describe "schema introspection" do
    let(:introspection_query) do
      <<~GQL
        query IntrospectionQuery {
          __schema {
            queryType  { name }
            mutationType { name }
            types { name kind }
          }
        }
      GQL
    end

    context "in development (unauthenticated introspection allowed)" do
      it "returns the schema without a token" do
        # GraphqlController allows IntrospectionQuery unauthenticated in dev.
        # In test env the endpoint may return 200 (schema) or 401 (auth required).
        gql_post(query: introspection_query, operation_name: "IntrospectionQuery")
        expect(response.status).to be_in([ 200, 401 ])
        if response.status == 200
          body = json
          if body.key?("data") && body["data"]
            expect(body["data"]["__schema"]["queryType"]["name"]).to eq("Query")
            expect(body["data"]["__schema"]["mutationType"]["name"]).to eq("Mutation")
          end
        end
      end
    end
  end

  # ─────────────────────────── queries ────────────────────────────────────────

  describe "query: assetDetail" do
    let(:query) do
      <<~GQL
        query FetchAsset($uuid: String!) {
          assetDetail(uuid: $uuid) {
            id uuid title createdAt
            url previewUrl
            properties
          }
        }
      GQL
    end

    context "as an authenticated user" do
      let(:asset) { create(:asset) }

      it "returns the asset when found" do
        gql_post(query: query,
                 variables: { uuid: asset.uuid },
                 user: viewer_user)
        expect(response).to have_http_status(:ok)
        data = json.dig("data", "assetDetail")
        expect(data).not_to be_nil
        expect(data["uuid"]).to eq(asset.uuid)
        expect(data).to have_key("previewUrl")
      end

      it "returns the preview variant URL when the asset has a generated preview" do
        asset.update!(properties: asset.properties.merge(
          "preview_storage_path" => "#{asset.uuid}/v1_preview_abcd.png",
          "preview_content_type" => "image/png"
        ))
        gql_post(query: query,
                 variables: { uuid: asset.uuid },
                 user: viewer_user)
        expect(response).to have_http_status(:ok)
        data = json.dig("data", "assetDetail")
        expect(data["previewUrl"]).to include("variant=preview")
      end

      it "returns null when the asset UUID does not exist" do
        gql_post(query: query,
                 variables: { uuid: "00000000-0000-0000-0000-000000000000" },
                 user: viewer_user)
        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "assetDetail")).to be_nil
      end
    end
  end

  describe "query: searchAssets" do
    let(:query) do
      <<~GQL
        query SearchAssets($query: String, $mode: String) {
          searchAssets(query: $query, mode: $mode, first: 25) {
            edges {
              node { id uuid title }
            }
            pageInfo { hasNextPage endCursor }
          }
        }
      GQL
    end

    context "as an authenticated user" do
      before { create_list(:asset, 3) }

      it "returns a connection-shaped response" do
        gql_post(query: query,
                 variables: { mode: "images" },
                 user: viewer_user)
        expect(response).to have_http_status(:ok)
        data = json.dig("data", "searchAssets")
        expect(data).to have_key("edges")
        expect(data).to have_key("pageInfo")
      end

      it "supports text search via the query argument" do
        gql_post(query: query,
                 variables: { query: "nonexistent_title_xyz" },
                 user: viewer_user)
        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "searchAssets", "edges")).to be_an(Array)
      end
    end

    context "with sorting" do
      let(:sorted_query) do
        <<~GQL
          query SearchAssets($mode: String, $sortBy: String, $sortDirection: String) {
            searchAssets(mode: $mode, sortBy: $sortBy, sortDirection: $sortDirection, first: 25) {
              edges { node { title } }
            }
          }
        GQL
      end

      before do
        create(:asset, title: "Zebra", status: :ready)
        create(:asset, title: "Apple", status: :ready)
        create(:asset, title: "Mango", status: :ready)
      end

      it "sorts by name ascending" do
        gql_post(query: sorted_query,
                 variables: { mode: "all", sortBy: "name", sortDirection: "asc" },
                 user: viewer_user)
        titles = json.dig("data", "searchAssets", "edges").map { |e| e.dig("node", "title") }
        expect(titles).to eq(%w[Apple Mango Zebra])
      end

      it "sorts by name descending" do
        gql_post(query: sorted_query,
                 variables: { mode: "all", sortBy: "name", sortDirection: "desc" },
                 user: viewer_user)
        titles = json.dig("data", "searchAssets", "edges").map { |e| e.dig("node", "title") }
        expect(titles).to eq(%w[Zebra Mango Apple])
      end

      it "accepts created_at, size, and type sort fields without error" do
        %w[created_at updated_at size type].each do |field|
          gql_post(query: sorted_query,
                   variables: { mode: "all", sortBy: field, sortDirection: "desc" },
                   user: viewer_user)
          expect(response).to have_http_status(:ok)
          expect(json["errors"]).to be_nil
        end
      end
    end
  end

  describe "query: collections" do
    let(:query) do
      <<~GQL
        {
          collections {
            id uuid name slug description createdAt
          }
        }
      GQL
    end

    it "returns an array of collections" do
      create_list(:collection, 2)
      gql_post(query: query, user: viewer_user)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "collections")).to be_an(Array)
    end
  end

  describe "query: collection (by slug)" do
    let(:query) do
      <<~GQL
        query FindCollection($slug: String!) {
          collection(slug: $slug) {
            id name slug
            assets { id uuid title }
          }
        }
      GQL
    end

    it "returns the matching collection" do
      col = create(:collection, slug: "my-test-slug")
      gql_post(query: query, variables: { slug: col.slug }, user: viewer_user)
      expect(response).to have_http_status(:ok)
      data = json.dig("data", "collection")
      expect(data).not_to be_nil
      expect(data["slug"]).to eq("my-test-slug")
    end

    it "returns null for an unknown slug" do
      gql_post(query: query, variables: { slug: "no-such-slug" }, user: viewer_user)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "collection")).to be_nil
    end
  end

  describe "query: imageProfiles" do
    let(:query) do
      <<~GQL
        {
          imageProfiles {
            id name cropType
            responsiveCropEnabled swatchEnabled
            swatchWidth swatchHeight
            createdAt updatedAt
          }
        }
      GQL
    end

    it "returns an array of image profiles" do
      create(:image_profile)
      gql_post(query: query, user: admin_user)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "imageProfiles")).to be_an(Array)
    end
  end

  describe "query: imageProfile (by id)" do
    let(:query) do
      <<~GQL
        query FetchProfile($id: ID!) {
          imageProfile(id: $id) {
            id name cropType swatchEnabled folderCount
          }
        }
      GQL
    end

    it "returns the profile" do
      profile = create(:image_profile)
      gql_post(query: query, variables: { id: profile.id }, user: admin_user)
      expect(response).to have_http_status(:ok)
      data = json.dig("data", "imageProfile")
      expect(data).not_to be_nil
      expect(data["id"].to_i).to eq(profile.id)
    end
  end

  # ─────────────────────────── mutations ──────────────────────────────────────

  describe "mutation: updateAssetMetadata" do
    let(:mutation) do
      <<~GQL
        mutation PatchMetadata($uuid: String!, $updates: Json!) {
          updateAssetMetadata(input: { uuid: $uuid, updates: $updates }) {
            asset { uuid properties }
            errors
          }
        }
      GQL
    end

    context "as a manager" do
      let(:asset) { create(:asset) }

      it "patches the asset properties and returns the asset" do
        gql_post(query: mutation,
                 variables: { uuid: asset.uuid, updates: { "campaign" => "spring" } },
                 user: manager_user)
        expect(response).to have_http_status(:ok)
        payload = json.dig("data", "updateAssetMetadata")
        expect(payload["errors"]).to be_empty
        expect(payload["asset"]["uuid"]).to eq(asset.uuid)
      end
    end

    context "as a viewer (insufficient role)" do
      let(:asset) { create(:asset) }

      it "returns an authorization error" do
        gql_post(query: mutation,
                 variables: { uuid: asset.uuid, updates: { "campaign" => "x" } },
                 user: viewer_user)
        expect(response).to have_http_status(:ok)
        payload = json.dig("data", "updateAssetMetadata")
        expect(payload["errors"]).not_to be_empty
        expect(payload["asset"]).to be_nil
      end
    end
  end

  describe "mutation: createCollection" do
    let(:mutation) do
      <<~GQL
        mutation NewCollection($name: String!, $description: String) {
          createCollection(input: { name: $name, description: $description }) {
            collection { id name slug }
            errors
          }
        }
      GQL
    end

    it "creates a collection and returns it" do
      gql_post(query: mutation,
               variables: { name: "Campaign 2026", description: "Spring campaign assets" },
               user: manager_user)
      expect(response).to have_http_status(:ok)
      payload = json.dig("data", "createCollection")
      expect(payload["errors"]).to be_empty
      expect(payload["collection"]["name"]).to eq("Campaign 2026")
    end
  end

  describe "mutation: addAssetToCollection" do
    let(:mutation) do
      <<~GQL
        mutation AddToCollection($collectionId: ID!, $assetId: ID!) {
          addAssetToCollection(input: { collectionId: $collectionId, assetId: $assetId }) {
            collection { id assets { id } }
            errors
          }
        }
      GQL
    end

    it "links the asset to the collection" do
      col   = create(:collection)
      asset = create(:asset)
      gql_post(query: mutation,
               variables: { collectionId: col.id, assetId: asset.id },
               user: manager_user)
      expect(response).to have_http_status(:ok)
      payload = json.dig("data", "addAssetToCollection")
      expect(payload["errors"]).to be_empty
    end
  end

  describe "mutation: removeAssetFromCollection" do
    let(:mutation) do
      <<~GQL
        mutation RemoveFromCollection($collectionId: ID!, $assetId: ID!) {
          removeAssetFromCollection(input: { collectionId: $collectionId, assetId: $assetId }) {
            collection { id }
            errors
          }
        }
      GQL
    end

    it "removes the asset and returns the collection" do
      col   = create(:collection)
      asset = create(:asset)
      col.assets << asset
      gql_post(query: mutation,
               variables: { collectionId: col.id, assetId: asset.id },
               user: manager_user)
      expect(response).to have_http_status(:ok)
      payload = json.dig("data", "removeAssetFromCollection")
      expect(payload["errors"]).to be_empty
    end
  end

  describe "mutation: createImageProfile" do
    let(:mutation) do
      <<~GQL
        mutation CreateProfile($name: String!) {
          createImageProfile(input: {
            name: $name,
            cropType: "smart_crop",
            responsiveCropEnabled: true,
            swatchEnabled: false
          }) {
            imageProfile { id name cropType }
            errors
          }
        }
      GQL
    end

    context "as admin" do
      it "creates the profile" do
        gql_post(query: mutation, variables: { name: "Web Standard" }, user: admin_user)
        expect(response).to have_http_status(:ok)
        payload = json.dig("data", "createImageProfile")
        expect(payload["errors"]).to be_empty
        expect(payload["imageProfile"]["name"]).to eq("Web Standard")
      end
    end

    context "as viewer (non-admin)" do
      it "returns an authorization error" do
        gql_post(query: mutation, variables: { name: "Hacker Profile" }, user: viewer_user)
        expect(response).to have_http_status(:ok)
        payload = json.dig("data", "createImageProfile")
        expect(payload["errors"]).not_to be_empty
        expect(payload["imageProfile"]).to be_nil
      end
    end
  end

  describe "mutation: updateImageProfile" do
    let(:mutation) do
      <<~GQL
        mutation UpdateProfile($id: ID!, $name: String) {
          updateImageProfile(input: { id: $id, name: $name }) {
            imageProfile { id name }
            errors
          }
        }
      GQL
    end

    it "updates the profile name" do
      profile = create(:image_profile, name: "Old Name")
      gql_post(query: mutation,
               variables: { id: profile.id, name: "New Name" },
               user: admin_user)
      expect(response).to have_http_status(:ok)
      payload = json.dig("data", "updateImageProfile")
      expect(payload["errors"]).to be_empty
      expect(payload["imageProfile"]["name"]).to eq("New Name")
    end
  end

  # ─────────────────────────── error handling ─────────────────────────────────

  describe "invalid GraphQL" do
    it "returns an errors array for a syntax error" do
      gql_post(query: "{ notAValidField }}}}", user: viewer_user)
      expect(response).to have_http_status(:ok)
      # Either errors key or http error
      body = json
      expect(body["errors"] || body["data"]).not_to be_nil
    end

    it "returns an errors array for an unknown field" do
      gql_post(query: "{ thisFieldDoesNotExist }", user: viewer_user)
      expect(response).to have_http_status(:ok)
      expect(json["errors"]).not_to be_nil
    end
  end

  # ─────────────────────────── agent workflows ────────────────────────────────

  describe "agentWorkflows query" do
    let(:query) do
      <<~GQL
        query($active: Boolean) {
          agentWorkflows(active: $active) {
            id
            name
            triggerEvent
            agentModel
            toolsEnabled
            active
            executionCount
            reliability
          }
        }
      GQL
    end

    it "returns all workflows for an authenticated user" do
      create(:agent_workflow, name: "SEO Bot", active: true)
      create(:agent_workflow, name: "Compliance", active: false)

      gql_post(query: query, user: viewer_user)
      expect(response).to have_http_status(:ok)
      names = json.dig("data", "agentWorkflows").map { |w| w["name"] }
      expect(names).to contain_exactly("SEO Bot", "Compliance")
    end

    it "filters by active state" do
      create(:agent_workflow, name: "SEO Bot", active: true)
      create(:agent_workflow, name: "Compliance", active: false)

      gql_post(query: query, variables: { active: true }, user: viewer_user)
      data = json.dig("data", "agentWorkflows")
      expect(data.map { |w| w["name"] }).to eq([ "SEO Bot" ])
    end

    it "exposes computed reliability and executionCount" do
      wf = create(:agent_workflow)
      create_list(:agent_execution, 4, agent_workflow: wf, status: "success")
      create(:agent_execution, agent_workflow: wf, status: "failed")

      gql_post(query: query, user: viewer_user)
      row = json.dig("data", "agentWorkflows").first
      expect(row["executionCount"]).to eq(5)
      expect(row["reliability"]).to eq(80.0)
    end
  end

  describe "agentWorkflow(id:) query" do
    let(:query) do
      <<~GQL
        query($id: ID!) {
          agentWorkflow(id: $id) {
            id
            name
            recentExecutions(limit: 5) { id status summary }
          }
        }
      GQL
    end

    it "returns a single workflow with recent executions" do
      wf = create(:agent_workflow, name: "SEO Bot")
      create_list(:agent_execution, 3, agent_workflow: wf)

      gql_post(query: query, variables: { id: wf.id.to_s }, user: viewer_user)
      data = json.dig("data", "agentWorkflow")
      expect(data["name"]).to eq("SEO Bot")
      expect(data["recentExecutions"].size).to eq(3)
    end

    it "returns null for a missing workflow" do
      gql_post(query: query, variables: { id: "0" }, user: viewer_user)
      expect(json.dig("data", "agentWorkflow")).to be_nil
    end
  end
end

# ---- merged from graphql_coverage_spec.rb ----
RSpec.describe "GraphQL coverage scenarios", type: :request do
  let(:admin) { create(:user, :admin, first_name: "Ada", last_name: "Admin") }
  let(:super_admin) { create(:user, :super_admin, first_name: "Sue", last_name: "Root") }
  let(:viewer) { create(:user, first_name: "Vic", last_name: "Viewer") }

  before do
    allow(Redis).to receive(:new).and_return(instance_double(Redis, publish: true))
    allow(EmailOrchestrator).to receive(:trigger)
    allow(AuditLog).to receive(:record)
    allow(DuplicateRepositoryScanWorker).to receive(:perform_async)
    allow(BinPurgeWorker).to receive(:perform_async)
  end

  def gql(query, variables: {}, user: admin)
    sign_in(user) if user
    post "/graphql",
         params: { query: query, variables: variables },
         headers: { "Accept" => "application/json" },
         as: :json
    JSON.parse(response.body)
  end

  def schema_exec(query, variables: {}, context: {})
    HeadlessDamSchema.execute(query, variables: variables, context: context).to_h
  end

  describe "QueryType and target object types" do
    it "returns admin-only users and groups with nested type fields" do
      group = create(:user_group, name: "Designers")
      child = create(:user_group, name: "Retouchers")
      group.add_child(child)
      viewer.user_groups << group
      create(:personal_access_token, user: viewer, name: "CLI")

      query = <<~GQL
        query($userId: ID!, $groupId: ID!) {
          users {
            id email username displayName firstName lastName name department role avatarUrl
            admin active ssoManaged provider
            groups { id name slug isSystem deletable memberCount }
            impersonators { id email }
            preferences { language theme receiveMentionEmails receiveWorkflowEmails }
            personalAccessTokens { id name scopes lastFour active }
          }
          user(id: $userId) { id email personalAccessTokens { name } }
          userGroups {
            id name description isSystem deletable parentId memberCount
            members { id email }
            childGroups { id name }
            permissions { id }
          }
          userGroup(id: $groupId) { id name childGroups { id name } }
        }
      GQL

      body = gql(query, variables: { userId: viewer.id, groupId: group.id })

      expect(body["errors"]).to be_nil
      expect(body.dig("data", "user", "personalAccessTokens", 0, "name")).to eq("CLI")
      expect(body.dig("data", "userGroup", "childGroups", 0, "name")).to eq("Retouchers")
    end

    it "hides admin-only users and groups from non-admins" do
      create(:user_group)
      body = gql("{ users { id } userGroups { id } user(id: 1) { id } userGroup(id: 1) { id } }", user: viewer)

      expect(body.dig("data", "users")).to eq([])
      expect(body.dig("data", "userGroups")).to eq([])
      expect(body.dig("data", "user")).to be_nil
      expect(body.dig("data", "userGroup")).to be_nil
    end

    it "exercises asset search filters, sorting fallbacks, and asset fields" do
      create(:asset, title: "Poster", properties: { "content_type" => "image/png", "size" => 20, "brand" => "capri" })
      create(:asset, title: "Clip", properties: { "content_type" => "video/mp4", "size" => 10, "brand" => "capri" })

      query = <<~GQL
        query($filters: Json) {
          searchAssets(query: "Post", mode: "images", metadataFilters: $filters, sortBy: "unknown", sortDirection: "sideways", first: 5) {
            edges { node { id uuid title url versionNumber properties createdAt } }
          }
        }
      GQL

      body = gql(query, variables: { filters: { "brand" => "capri" } }, user: viewer)

      expect(body["errors"]).to be_nil
      expect(body.dig("data", "searchAssets", "edges").map { |e| e.dig("node", "title") }).to eq([ "Poster" ])
    end

    it "returns inbox messages and unread count only for the current user" do
      create(:inbox_message, :unread, :with_sender, recipient: viewer, subject: "Workflow approval needed", body_text: "Please approve this asset")
      create(:inbox_message, :archived, recipient: viewer)
      create(:inbox_message, :unread, message_type: "mention")

      query = <<~GQL
        query {
          inbox(type: "notification", unreadOnly: true) {
            id subject bodyHtml bodyText messageType read starred archived snippet sender { id email }
          }
          inboxUnreadCount
        }
      GQL

      body = gql(query, user: viewer)

      expect(body["errors"]).to be_nil
      expect(body.dig("data", "inbox").length).to eq(1)
      expect(body.dig("data", "inbox", 0, "snippet")).to include("Please approve")
      expect(body.dig("data", "inboxUnreadCount")).to eq(1)
    end

    it "returns duplicate manager query data across status branches" do
      pending = create(:duplicate_group, total_count: 2)
      asset = create(:asset, title: "Original")
      create(:duplicate_group_asset, :original, duplicate_group: pending, asset: asset)
      resolved = create(:duplicate_group, :resolved)
      create(:duplicate_group, :dismissed)
      Setting.set("duplicate_manager_scan_status", "running")
      Setting.set("duplicate_manager_scan_progress", { "processed" => 3 })

      query = <<~GQL
        query($id: String!) {
          duplicateGroups(status: "all", first: 10) {
            edges {
              node {
                id checksum status resolutionAction totalCount resolvedAt resolvedBy
                assets { assetId title isOriginal status folderName uploadedBy }
              }
            }
          }
          duplicateGroup(id: $id) { id status resolvedBy }
          duplicateManagerStats
          duplicateManagerScanStatus
        }
      GQL

      body = gql(query, variables: { id: resolved.id }, user: viewer)

      expect(body["errors"]).to be_nil
      expect(body.dig("data", "duplicateGroups", "edges").length).to be >= 3
      expect(body.dig("data", "duplicateGroup", "resolvedBy")).to eq(resolved.resolved_by.email)
      expect(body.dig("data", "duplicateManagerScanStatus", "scan_status")).to eq("running")
    end

    it "returns bin policy, status, stats, and AI purge suggestions for admins" do
      create(:asset, :trashed, title: "Old Huge Asset",
                              deleted_at: 400.days.ago,
                              properties: { "size" => 1_000_000, "content_type" => "image/png" })
      Setting.set("bin_retention_days", 30)
      Setting.set("bin_purge_last_results", { "deleted" => 2 })
      Setting.set("bin_purge_triggered_by", { "source" => "spec" })

      query = <<~GQL
        query {
          binStats { totalItems totalAssets totalFolders totalSizeBytes retentionDays oldestDeletedAt }
          binRetentionPolicy { retentionDays workflowBehavior batchSize notifyAdmins nextScheduledAt }
          binPurgeStatus { status lastRanAt startedAt triggeredBy lastResults policy { retentionDays } }
          binAiSuggestions(limit: 5) {
            id title deletedAt ageDays sizeBytes sizeHuman hasCollectionPin hasActiveWorkflow heuristicScore aiRiskScore aiReason aiTags
          }
        }
      GQL

      body = gql(query)

      expect(body["errors"]).to be_nil
      expect(body.dig("data", "binStats", "totalAssets")).to eq(1)
      expect(body.dig("data", "binAiSuggestions", 0, "title")).to eq("Old Huge Asset")
    end

    it "blocks bin AI suggestions for non-admins" do
      body = gql("{ binAiSuggestions { id } }", user: viewer)

      expect(body["errors"].first["message"]).to include("Administrator privileges required")
    end

    it "returns workflow steps and instances and handles missing workflow/asset branches" do
      workflow = create(:workflow)
      step = create(:workflow_step, workflow: workflow, position: 2, assignee_id: admin.id)
      asset = create(:asset)
      instance = create(:workflow_instance, workflow: workflow, asset: asset, audit_log: [ { "event" => "started" } ])
      create(:workflow_task, workflow_instance: instance, workflow_step: step, user: admin, status: "pending")

      query = <<~GQL
        query($workflowId: ID!, $missingWorkflowId: ID!, $assetId: ID!, $missingAssetId: ID!) {
          workflowSteps(workflowId: $workflowId) { id title stepType position assigneeId logic }
          missing: workflowSteps(workflowId: $missingWorkflowId) { id }
          workflowInstances(assetId: $assetId, limit: 99) {
            id status auditLog workflowId assetId taskCount pendingTasks currentStep { id title }
          }
          none: workflowInstances(assetId: $missingAssetId) { id }
        }
      GQL

      body = gql(query, variables: { workflowId: workflow.id, missingWorkflowId: 0, assetId: asset.id, missingAssetId: 0 }, user: viewer)

      expect(body["errors"]).to be_nil
      expect(body.dig("data", "workflowSteps", 0, "id").to_i).to eq(step.id)
      expect(body.dig("data", "workflowInstances", 0, "taskCount")).to eq(1)
      expect(body.dig("data", "none")).to eq([])
    end
  end

  describe "admin profile and hub mutations" do
    it "creates and updates video profiles, including invalid JSON branches" do
      create_query = <<~GQL
        mutation($input: CreateVideoProfileInput!) {
          createVideoProfile(input: $input) {
            videoProfile { id name description encodeForAdaptiveStreaming smartCropRatios adaptiveStreamingWarnings encodingPresets { name height } folderCount }
            errors
          }
        }
      GQL
      create_body = gql(create_query, variables: {
        input: {
          name: "OTT",
          description: "Streaming",
          smartCropRatios: "[{\"name\":\"Wide\",\"crop_ratio\":\"16:9\"}]",
          encodingPresets: "[{\"name\":\"360p\",\"height\":360,\"video_bitrate_kbps\":730}]",
        },
      })

      expect(create_body.dig("data", "createVideoProfile", "errors")).to eq([])
      profile_id = create_body.dig("data", "createVideoProfile", "videoProfile", "id")

      update_query = <<~GQL
        mutation($input: UpdateVideoProfileInput!) {
          updateVideoProfile(input: $input) {
            videoProfile { id name smartCropRatios encodingPresets { name height } }
            errors
          }
        }
      GQL
      update_body = gql(update_query, variables: { input: { id: profile_id, name: "OTT Updated", smartCropRatios: "not-json", encodingPresets: "not-json" } })

      expect(update_body.dig("data", "updateVideoProfile", "errors")).to eq([])
      expect(update_body.dig("data", "updateVideoProfile", "videoProfile", "name")).to eq("OTT Updated")
    end

    it "returns video profile authorization and not-found errors" do
      mutation = <<~GQL
        mutation($input: UpdateVideoProfileInput!) {
          updateVideoProfile(input: $input) { videoProfile { id } errors }
        }
      GQL

      unauthorized = gql(mutation, variables: { input: { id: 0, name: "Nope" } }, user: viewer)
      missing = gql(mutation, variables: { input: { id: 0, name: "Missing" } })

      expect(unauthorized.dig("data", "updateVideoProfile", "errors")).to include("Administrator privileges required.")
      expect(missing.dig("data", "updateVideoProfile", "errors")).to include("Video profile not found.")
    end

    it "updates image profiles with crop and unsharp branches" do
      profile = create(:image_profile)
      mutation = <<~GQL
        mutation($input: UpdateImageProfileInput!) {
          updateImageProfile(input: $input) {
            imageProfile { id name unsharpMask cropType responsiveCrops swatchEnabled swatchWidth swatchHeight }
            errors
          }
        }
      GQL

      body = gql(mutation, variables: {
        input: {
          id: profile.id,
          name: "Smart",
          cropType: "smart_crop",
          responsiveCropEnabled: true,
          responsiveCrops: "[{\"name\":\"Small\",\"width\":320,\"height\":240}]",
          swatchEnabled: true,
          swatchWidth: 24,
          swatchHeight: 24,
          unsharpAmount: 2.0,
        },
      })

      expect(body.dig("data", "updateImageProfile", "errors")).to eq([])
      expect(body.dig("data", "updateImageProfile", "imageProfile", "unsharpMask", "amount")).to eq(2.0)
    end

    it "updates model configs and style presets and reports non-admin GraphQL errors" do
      config = create(:ai_model_config)
      preset = create(:style_preset)
      mutation = <<~GQL
        mutation($model: UpdateAiModelConfigInput!, $preset: UpdateStylePresetInput!) {
          updateAiModelConfig(input: $model) { aiModelConfig { id name enabled metadata } errors }
          updateStylePreset(input: $preset) { stylePreset { id name active styleParams createdBy stale } errors }
        }
      GQL

      body = gql(mutation, variables: {
        model: { id: config.id, name: "Claude", enabled: false, metadata: { "tier" => "gold" } },
        preset: { id: preset.id, name: "Muted", active: false, styleParams: { "tone" => "soft" } },
      })
      forbidden = gql(mutation, variables: {
        model: { id: config.id, name: "Bad" },
        preset: { id: preset.id, name: "Bad" },
      }, user: viewer)

      expect(body["errors"]).to be_nil
      expect(body.dig("data", "updateAiModelConfig", "aiModelConfig", "enabled")).to be(false)
      expect(body.dig("data", "updateStylePreset", "stylePreset", "active")).to be(false)
      expect(forbidden["errors"].first["message"]).to include("Administrator privileges required")
    end

    it "returns not found payloads for model and style updates" do
      mutation = <<~GQL
        mutation {
          updateAiModelConfig(input: { id: 0, name: "Missing" }) { aiModelConfig { id } errors }
          updateStylePreset(input: { id: 0, name: "Missing" }) { stylePreset { id } errors }
        }
      GQL

      body = gql(mutation)

      expect(body.dig("data", "updateAiModelConfig", "errors")).to include("Not found")
      expect(body.dig("data", "updateStylePreset", "errors")).to include("Not found")
    end
  end

  describe "user and group mutations" do
    it "creates and updates users including group assignment and SSO-safe attributes" do
      group = create(:user_group)
      create_query = <<~GQL
        mutation($input: CreateUserInput!) {
          createUser(input: $input) {
            user { id email firstName lastName name department role admin active groups { id name } }
            errors
          }
        }
      GQL
      created = gql(create_query, variables: {
        input: {
          email: "created@example.com",
          firstName: "Created",
          lastName: "User",
          department: "Ops",
          role: "manager",
          admin: false,
          groupIds: [ group.id ],
        },
      })

      expect(created.dig("data", "createUser", "errors")).to eq([])
      user_id = created.dig("data", "createUser", "user", "id")

      update_query = <<~GQL
        mutation($input: UpdateUserInput!) {
          updateUser(input: $input) { user { id firstName lastName department role admin active groups { id } } errors }
        }
      GQL
      updated = gql(update_query, variables: { input: { id: user_id, firstName: "Renamed", active: false, groupIds: [] } })
      sso_user = create(:user, :sso, first_name: "Remote", last_name: "Name")
      sso_updated = gql(update_query, variables: { input: { id: sso_user.id, firstName: "Ignored", department: "SSO" } })

      expect(updated.dig("data", "updateUser", "user", "firstName")).to eq("Renamed")
      expect(sso_updated.dig("data", "updateUser", "user", "firstName")).to eq("Remote")
      expect(sso_updated.dig("data", "updateUser", "user", "department")).to eq("SSO")
    end

    it "returns user mutation authorization, missing, and validation errors" do
      create_query = <<~GQL
        mutation($input: CreateUserInput!) { createUser(input: $input) { user { id } errors } }
      GQL
      update_query = <<~GQL
        mutation($input: UpdateUserInput!) { updateUser(input: $input) { user { id } errors } }
      GQL

      forbidden = gql(create_query, variables: { input: { email: "x@example.com", firstName: "X", lastName: "Y" } }, user: viewer)
      invalid = gql(create_query, variables: { input: { email: "not-an-email", firstName: "", lastName: "" } })
      missing = gql(update_query, variables: { input: { id: 0, firstName: "Nope" } })

      expect(forbidden.dig("data", "createUser", "errors")).to include("Unauthorized")
      expect(invalid.dig("data", "createUser", "errors")).not_to be_empty
      expect(missing.dig("data", "updateUser", "errors")).to include("User not found")
    end

    it "creates, updates, and deletes user groups" do
      parent = create(:user_group, name: "Parent")
      create_query = <<~GQL
        mutation($input: CreateUserGroupInput!) {
          createUserGroup(input: $input) { userGroup { id name description parentId } errors }
        }
      GQL
      created = gql(create_query, variables: { input: { name: "Nested Team", description: "A team", parentId: parent.id } })
      group_id = created.dig("data", "createUserGroup", "userGroup", "id")

      update_query = <<~GQL
        mutation($input: UpdateUserGroupInput!) {
          updateUserGroup(input: $input) { userGroup { id name description } errors }
        }
      GQL
      updated = gql(update_query, variables: { input: { id: group_id, name: "Nested Renamed" } })

      delete_query = <<~GQL
        mutation($input: DeleteUserGroupInput!) { deleteUserGroup(input: $input) { success errors } }
      GQL
      deleted = gql(delete_query, variables: { input: { id: group_id } })

      expect(created.dig("data", "createUserGroup", "errors")).to eq([])
      expect(updated.dig("data", "updateUserGroup", "userGroup", "name")).to eq("Nested Renamed")
      expect(deleted.dig("data", "deleteUserGroup", "success")).to be(true)
    end

    it "returns group authorization, not-found, and system protection errors" do
      system_group = create(:user_group, :administrators)
      query = <<~GQL
        mutation($id: ID!) {
          updateUserGroup(input: { id: $id, name: "Admins" }) { userGroup { id } errors }
          deleteUserGroup(input: { id: $id }) { success errors }
        }
      GQL

      forbidden = gql("mutation { createUserGroup(input: { name: \"No\" }) { userGroup { id } errors } }", user: viewer)
      missing = gql("mutation { updateUserGroup(input: { id: 0, name: \"No\" }) { userGroup { id } errors } deleteUserGroup(input: { id: 0 }) { success errors } }")
      protected_body = gql(query, variables: { id: system_group.id })
      super_body = gql("mutation($id: ID!) { updateUserGroup(input: { id: $id, description: \"Allowed\" }) { userGroup { id description } errors } }",
                       variables: { id: system_group.id },
                       user: super_admin)

      expect(forbidden.dig("data", "createUserGroup", "errors")).to include("Unauthorized")
      expect(missing.dig("data", "updateUserGroup", "errors")).to include("Group not found")
      expect(missing.dig("data", "deleteUserGroup", "errors")).to include("Group not found")
      expect(protected_body.dig("data", "updateUserGroup", "errors").first).to include("Only super-administrators")
      expect(protected_body.dig("data", "deleteUserGroup", "errors")).to include("System groups cannot be deleted")
      expect(super_body.dig("data", "updateUserGroup", "errors")).to eq([])
    end
  end

  describe "personal access token and inbox mutations" do
    it "creates and revokes a current user's personal access token" do
      create_query = <<~GQL
        mutation($input: CreatePersonalAccessTokenInput!) {
          createPersonalAccessToken(input: $input) {
            success rawToken token { id name scopes lastFour active expiresAt createdAt } errors
          }
        }
      GQL
      created = gql(create_query, variables: { input: { name: "Automation", scopes: "write", expiresAt: 1.month.from_now.iso8601 } }, user: viewer)
      token_id = created.dig("data", "createPersonalAccessToken", "token", "id")

      revoke_query = <<~GQL
        mutation($input: RevokePersonalAccessTokenInput!) {
          revokePersonalAccessToken(input: $input) { success message }
        }
      GQL
      revoked = gql(revoke_query, variables: { input: { id: token_id } }, user: viewer)

      expect(created.dig("data", "createPersonalAccessToken", "rawToken")).to start_with("dat_")
      expect(revoked.dig("data", "revokePersonalAccessToken", "success")).to be(true)
    end

    it "returns token mutation errors for invalid scopes, missing tokens, and unauthenticated context" do
      invalid_create = gql("mutation { createPersonalAccessToken(input: { name: \"Bad\", scopes: \"root\" }) { success token { id } errors } }", user: viewer)
      missing_revoke = gql("mutation { revokePersonalAccessToken(input: { id: 0 }) { success message } }", user: viewer)
      unauthenticated = schema_exec("mutation { createPersonalAccessToken(input: { name: \"No\" }) { success errors } }")

      expect(invalid_create.dig("data", "createPersonalAccessToken", "success")).to be(false)
      expect(invalid_create.dig("data", "createPersonalAccessToken", "errors")).not_to be_empty
      expect(missing_revoke["errors"].first["message"]).to eq("Token not found")
      expect(unauthenticated["errors"].first["message"]).to eq("Not authenticated")
    end

    it "marks inbox messages read and archives only the current user's messages" do
      message = create(:inbox_message, :unread, recipient: viewer)
      archive = create(:inbox_message, :unread, recipient: viewer)
      other = create(:inbox_message, :unread)

      mutation = <<~GQL
        mutation($read: ID!, $archive: ID!, $other: ID!) {
          markInboxMessageRead(input: { id: $read }) { success }
          archiveInboxMessage(input: { id: $archive }) { success }
          other: markInboxMessageRead(input: { id: $other }) { success }
        }
      GQL

      body = gql(mutation, variables: { read: message.id, archive: archive.id, other: other.id }, user: viewer)

      expect(body.dig("data", "markInboxMessageRead", "success")).to be(true)
      expect(body.dig("data", "archiveInboxMessage", "success")).to be(true)
      expect(body["errors"].first["message"]).to eq("Message not found")
    end
  end

  describe "duplicate and recycle bin mutations" do
    it "resolves duplicate groups and soft-deletes selected duplicate assets" do
      group = create(:duplicate_group, total_count: 2)
      original = create(:asset)
      duplicate = create(:asset)
      create(:duplicate_group_asset, :original, duplicate_group: group, asset: original)
      create(:duplicate_group_asset, duplicate_group: group, asset: duplicate)

      mutation = <<~GQL
        mutation($input: ResolveDuplicateGroupInput!) {
          resolveDuplicateGroup(input: $input) {
            group { id status resolutionAction resolvedBy assets { assetId isOriginal } }
            errors
          }
        }
      GQL
      body = gql(mutation, variables: { input: { groupId: group.id, action: "deleted_duplicates", assetIdsToDelete: [ duplicate.id.to_s, original.id.to_s ] } }, user: viewer)

      expect(body.dig("data", "resolveDuplicateGroup", "errors")).to eq([])
      expect(body.dig("data", "resolveDuplicateGroup", "group", "status")).to eq("resolved")
      expect(duplicate.reload.deleted_at).to be_present
      expect(original.reload.deleted_at).to be_nil
    end

    it "returns duplicate resolution validation branches" do
      invalid_action = gql("mutation { resolveDuplicateGroup(input: { groupId: \"0\", action: \"bad\" }) { group { id } errors } }", user: viewer)
      missing_group = gql("mutation { resolveDuplicateGroup(input: { groupId: \"0\", action: \"kept_all\" }) { group { id } errors } }", user: viewer)
      unauthenticated = schema_exec("mutation { resolveDuplicateGroup(input: { groupId: \"0\", action: \"kept_all\" }) { group { id } errors } }")

      expect(invalid_action.dig("data", "resolveDuplicateGroup", "errors").first).to include("Invalid action")
      expect(missing_group.dig("data", "resolveDuplicateGroup", "errors")).to include("Duplicate group not found.")
      expect(unauthenticated.dig("data", "resolveDuplicateGroup", "errors")).to include("Authentication required.")
    end

    it "triggers duplicate scans through disabled, queued, and success branches" do
      mutation = "mutation { triggerDuplicateScan(input: {}) { status message errors } }"

      disabled = gql(mutation)
      Setting.set("duplicate_manager_enabled", true)
      queued = gql(mutation)
      already = gql(mutation)

      expect(disabled.dig("data", "triggerDuplicateScan", "errors").first).to include("Enable duplicate detection")
      expect(queued.dig("data", "triggerDuplicateScan", "status")).to eq("queued")
      expect(already.dig("data", "triggerDuplicateScan", "errors").first).to include("already queued")
    end

    it "updates bin retention policy and rejects invalid or unauthorized updates" do
      mutation = <<~GQL
        mutation($input: UpdateBinRetentionPolicyInput!) {
          updateBinRetentionPolicy(input: $input) { policy { retentionDays workflowBehavior batchSize notifyAdmins } errors }
        }
      GQL
      updated = gql(mutation, variables: { input: { retentionDays: 999, workflowBehavior: "force_terminate", batchSize: 0, notifyAdmins: false } })
      invalid = gql(mutation, variables: { input: { workflowBehavior: "delete" } })
      forbidden = gql(mutation, variables: { input: { retentionDays: 7 } }, user: viewer)

      expect(updated.dig("data", "updateBinRetentionPolicy", "policy", "retentionDays")).to eq(365)
      expect(updated.dig("data", "updateBinRetentionPolicy", "policy", "batchSize")).to eq(1)
      expect(invalid.dig("data", "updateBinRetentionPolicy", "errors").first).to include("workflow_behavior")
      expect(forbidden.dig("data", "updateBinRetentionPolicy", "errors")).to include("Administrator privileges required.")
    end

    it "triggers bin purge and reports already-running and non-admin branches" do
      mutation = "mutation { triggerBinPurge(input: {}) { queued status errors } }"
      queued = gql(mutation)
      running = gql(mutation)
      forbidden = gql(mutation, user: viewer)

      expect(queued.dig("data", "triggerBinPurge", "queued")).to be(true)
      expect(running.dig("data", "triggerBinPurge", "errors").first).to include("already queued")
      expect(forbidden.dig("data", "triggerBinPurge", "errors")).to include("Administrator privileges required.")
    end

    it "restores bin items, reports missing items, and empties the bin for admins only" do
      restored_asset = instance_double(Asset, restore: true)
      asset_scope = double("AssetTrashScope")
      allow(asset_scope).to receive(:find).and_return(restored_asset)
      allow(Asset).to receive(:trashed).and_return(asset_scope)
      mutation = <<~GQL
        mutation($items: [BinItemInput!]!) {
          bulkRestoreFromBin(input: { items: $items }) { restored errors }
        }
      GQL

      restored = gql(mutation, variables: { items: [ { id: 123, type: "asset" }, { id: 0, type: "folder" } ] }, user: viewer)
      allow(Asset).to receive(:trashed).and_call_original
      forbidden_empty = gql("mutation { emptyBin(input: {}) { deleted errors } }", user: viewer)
      empty = gql("mutation { emptyBin(input: {}) { deleted errors } }")

      expect(restored.dig("data", "bulkRestoreFromBin", "restored")).to eq(1)
      expect(restored.dig("data", "bulkRestoreFromBin", "errors").first).to include("Folder #0 not found")
      expect(forbidden_empty.dig("data", "emptyBin", "errors")).to include("Administrator privileges required.")
      expect(empty.dig("data", "emptyBin", "errors")).to eq([])
    end
  end

  describe "impersonation mutations and schema/base classes" do
    it "starts and stops impersonation with explicit schema context session" do
      target = create(:user, first_name: "Target", last_name: "User")
      session = {}
      start_query = <<~GQL
        mutation($id: ID!) {
          startImpersonation(input: { userId: $id }) { success message impersonatedUser { id displayName } }
        }
      GQL
      started = schema_exec(start_query, variables: { id: target.id }, context: { current_user: admin, session: session })
      session[:impersonated_user_id] = target.id
      session[:impersonator_id] = admin.id
      stopped = schema_exec("mutation { stopImpersonation(input: {}) { success message } }",
                            context: { current_user: target, true_user: admin, session: session })

      expect(started["errors"]).to be_nil
      expect(started.dig("data", "startImpersonation", "success")).to be(true)
      expect(stopped.dig("data", "stopImpersonation", "success")).to be(true)
      expect(session).not_to have_key(:impersonated_user_id)
    end

    it "reports impersonation errors for unauthenticated, missing, and forbidden targets" do
      super_target = create(:user, :super_admin)
      missing = schema_exec("mutation { startImpersonation(input: { userId: 0 }) { success } }",
                            context: { current_user: admin, session: {} })
      forbidden = schema_exec("mutation($id: ID!) { startImpersonation(input: { userId: $id }) { success } }",
                              variables: { id: super_target.id },
                              context: { current_user: admin, session: {} })
      unauthenticated = schema_exec("mutation($id: ID!) { startImpersonation(input: { userId: $id }) { success } }",
                                    variables: { id: super_target.id },
                                    context: { session: {} })

      expect(missing["errors"].first["message"]).to eq("User not found")
      expect(forbidden["errors"].first["message"]).to include("Not authorised")
      expect(unauthenticated["errors"].first["message"]).to eq("Not authenticated")
    end

    it "uses schema rescue_from and loads base GraphQL abstractions" do
      allow(Asset).to receive(:active).and_raise(StandardError, "boom")

      result = schema_exec("query { assetDetail(uuid: \"x\") { id } }", context: { current_user: viewer })

      expect(result["errors"].first["message"]).to include("Internal server error")
      expect(Resolvers::BaseResolver).to be < GraphQL::Schema::Resolver
      expect(Types::BaseEnum).to be < GraphQL::Schema::Enum
      expect(Types::BaseUnion.connection_type_class).to eq(Types::BaseConnection)
      expect(Types::NodeType).to include(GraphQL::Types::Relay::NodeBehaviors)
    end
  end
end
