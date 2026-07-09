# GraphQL query entry point — all read-only operations are defined here.
#
# == Available fields
#
# | Field | Return type | Description |
# |-------|-------------|-------------|
# | +assetDetail(uuid: ID!)+ | {Types::AssetType} | Fetch a single active asset by UUID |
# | +searchAssets(query, mode, metadataFilters)+ | [{Types::AssetType}] (connection) | Paginated asset search with optional facets |
# | +collections+ | [{Types::CollectionType}] | All active collections ordered by creation date |
# | +collection(slug: String!)+ | {Types::CollectionType} | Single collection by URL slug |
# | +imageProfiles+ | [{Types::ImageProfileType}] | All active image processing profiles |
# | +imageProfile(id: ID!)+ | {Types::ImageProfileType} | Single image profile by database ID |
# | +videoProfiles+ | [{Types::VideoProfileType}] | All active video processing profiles |
# | +videoProfile(id: ID!)+ | {Types::VideoProfileType} | Single video profile by database ID |
#
# == Search behaviour (+searchAssets+)
#
# * +query+ — case-insensitive ILIKE title match.
# * +mode+  — +"images"+ (default) restricts results to +image/*+ content type;
#   pass any other value to search all asset types.
# * +metadataFilters+ — a free-form JSON key-value map applied as exact-match
#   JSONB property filters (e.g. +{ "dam:language_code": "en" }+).
# * +sortBy+ — +name+ (default), +created_at+, +updated_at+, +size+, or +type+.
# * +sortDirection+ — +asc+ (default) or +desc+.
#
# @see Types::AssetType
# @see Types::CollectionType
# @see Types::ImageProfileType
module Types
  class QueryType < Types::BaseObject
    description "The master query entry point for data recovery."

    # Returns a single active asset by its external UUID.
    #
    # @param uuid [String] the asset's public UUID (not the database integer ID)
    # @return [Types::AssetType, nil] +nil+ when not found or soft-deleted
    field :asset_detail, Types::AssetType, null: true do
      argument :uuid, String, required: true
    end

    # Paginated, filterable search over all active assets.
    #
    # @param query   [String, nil]  case-insensitive title substring
    # @param mode    [String]       +"images"+ (default) or any string to search all types
    # @param metadata_filters [Hash, nil] JSONB property key→value strict-match map
    # @param sort_by [String] field to order results by: +name+, +created_at+,
    #   +updated_at+, +size+, or +type+ (default +name+)
    # @param sort_direction [String] +asc+ (default) or +desc+
    # @return [GraphQL::Pagination::Connection<Types::AssetType>]
    field :search_assets, Types::AssetType.connection_type, null: false do
      argument :query,            String,         required: false
      argument :mode,             String,         required: false, default_value: "images"
      argument :metadata_filters, Types::JsonType, required: false,
               description: "Key-value map for strict JSONB matching."
      argument :sort_by, String, required: false, default_value: "name",
               description: "Sort field: name, created_at, updated_at, size, or type."
      argument :sort_direction, String, required: false, default_value: "asc",
               description: "Sort direction: asc or desc."
    end

    def asset_detail(uuid:)
      Asset.active.find_by(uuid: uuid)
    end

    # Allowed sort fields mapped to SQL ordering expressions.
    ASSET_SORT_COLUMNS = {
      "name"       => "title",
      "created_at" => "created_at",
      "updated_at" => "updated_at",
      # size & type live in the JSONB properties column
      "size"       => "(properties->>'size')::bigint",
      "type"       => "properties->>'content_type'",
    }.freeze

    def search_assets(query: nil, mode: "images", metadata_filters: nil,
                      sort_by: "name", sort_direction: "asc")
      scope = Asset.active
      scope = scope.where("title ILIKE ?", "%#{query}%") if query.present?
      scope = scope.where("properties->>'content_type' ILIKE 'image/%'") if mode == "images"

      if metadata_filters.present?
        metadata_filters.each do |key, value|
          scope = scope.where("properties->>:key = :value", key: key, value: value)
        end
      end

      column    = ASSET_SORT_COLUMNS[sort_by.to_s] || ASSET_SORT_COLUMNS["name"]
      direction = sort_direction.to_s == "desc" ? "DESC" : "ASC"
      scope.order(Arel.sql("#{column} #{direction} NULLS LAST"))
    end

    # Returns all active, non-expired collections ordered newest-first.
    #
    # @return [Array<Types::CollectionType>]
    field :collections, [ Types::CollectionType ], null: false do
      description "Retrieve all active collections for the current workspace"
    end

    def collections
      Collection.active.order(created_at: :desc)
    end

    # Finds a single active collection by its URL-friendly slug.
    #
    # @param slug [String] the collection's unique slug
    # @return [Types::CollectionType, nil]
    field :collection, Types::CollectionType, null: true do
      description "Find a specific collection by its URL-friendly slug"
      argument :slug, String, required: true
    end

    def collection(slug:)
      Collection.active.find_by(slug: slug)
    end

    # Returns all active image processing profiles sorted alphabetically.
    #
    # @return [Array<Types::ImageProfileType>]
    field :image_profiles, [ Types::ImageProfileType ], null: false do
      description "List all active Image Processing Profiles"
    end

    def image_profiles
      ImageProfile.active.order(name: :asc)
    end

    # Finds an active image processing profile by its database ID.
    #
    # @param id [ID] the profile's database primary key
    # @return [Types::ImageProfileType, nil]
    field :image_profile, Types::ImageProfileType, null: true do
      description "Find an Image Processing Profile by ID"
      argument :id, ID, required: true
    end

    def image_profile(id:)
      ImageProfile.active.find_by(id: id)
    end

    # Returns all active video processing profiles sorted alphabetically.
    #
    # @return [Array<Types::VideoProfileType>]
    field :video_profiles, [ Types::VideoProfileType ], null: false do
      description "List all active Video Processing Profiles"
    end

    def video_profiles
      VideoProfile.active.order(name: :asc)
    end

    # Finds an active video processing profile by its database ID.
    #
    # @param id [ID] the profile's database primary key
    # @return [Types::VideoProfileType, nil]
    field :video_profile, Types::VideoProfileType, null: true do
      description "Find a Video Processing Profile by ID"
      argument :id, ID, required: true
    end

    def video_profile(id:)
      VideoProfile.active.find_by(id: id)
    end

    field :inbox, [ Types::InboxMessageType ], null: false do
      description "Recent inbox messages for the current user"
      argument :type, String, required: false
      argument :unread_only, Boolean, required: false
    end

    def inbox(type: nil, unread_only: false)
      user = context[:current_user]
      return [] unless user

      scope = user.inbox_messages.active.recent
      scope = scope.by_type(type) if type.present?
      scope = scope.unread if unread_only
      scope.limit(50)
    end

    field :inbox_unread_count, Integer, null: false, description: "Unread inbox count for the current user"

    def inbox_unread_count
      context[:current_user]&.inbox_messages&.active&.unread&.count || 0
    end

    # -------------------------------------------------------------------------
    # Custom Workflow Nodes (Plugin SDK, admin only)
    # -------------------------------------------------------------------------

    field :custom_node_definitions, [ Types::CustomNodeDefinitionType ], null: false do
      description "List custom workflow node manifests (admin only)"
      argument :status, String, required: false, description: "Filter by draft, enabled, or disabled"
    end

    def custom_node_definitions(status: nil)
      return [] unless context[:current_user]&.admin?

      scope = CustomNodeDefinition.includes(:created_by).order(updated_at: :desc)
      scope = scope.where(status: status) if status.present?
      scope
    end

    field :custom_node_definition, Types::CustomNodeDefinitionType, null: true do
      description "Find a custom workflow node manifest by ID (admin only)"
      argument :id, ID, required: true
    end

    def custom_node_definition(id:)
      return nil unless context[:current_user]&.admin?

      CustomNodeDefinition.find_by(id: id)
    end

    # -------------------------------------------------------------------------
    # Agent Workflows (AI Automations)
    # -------------------------------------------------------------------------

    # Returns all agent workflows, most-recently-updated first.
    #
    # @return [Array<Types::AgentWorkflowType>]
    field :agent_workflows, [ Types::AgentWorkflowType ], null: false do
      description "List all AI agent workflows"
      argument :active, Boolean, required: false, description: "Filter by active state"
    end

    def agent_workflows(active: nil)
      scope = AgentWorkflow.order(updated_at: :desc)
      scope = scope.where(active: active) unless active.nil?
      scope
    end

    # Finds a single agent workflow by its database ID.
    #
    # @param id [ID] the workflow's database primary key
    # @return [Types::AgentWorkflowType, nil]
    field :agent_workflow, Types::AgentWorkflowType, null: true do
      description "Find an AI agent workflow by ID"
      argument :id, ID, required: true
    end

    def agent_workflow(id:)
      AgentWorkflow.find_by(id: id)
    end

    # -------------------------------------------------------------------------
    # AI Batch Tasks (admin only)
    # -------------------------------------------------------------------------

    # Returns AI batch jobs, most-recent first (admin only).
    #
    # @param status [String, nil] optional status filter
    # @return [Array<Types::AiBatchJobType>]
    field :ai_batch_jobs, [ Types::AiBatchJobType ], null: false do
      description "List AI batch task runs (admin only)"
      argument :status, String, required: false, description: "Filter by status"
      argument :limit, Integer, required: false, default_value: 25
    end

    def ai_batch_jobs(status: nil, limit: 25)
      return [] unless context[:current_user]&.admin?

      scope = AiBatchJob.recent.limit(limit.to_i.clamp(1, 100))
      scope = scope.where(status: status) if status.present?
      scope
    end

    # Finds a single AI batch job by ID (admin only).
    #
    # @param id [ID]
    # @return [Types::AiBatchJobType, nil]
    field :ai_batch_job, Types::AiBatchJobType, null: true do
      description "Find an AI batch job by ID (admin only)"
      argument :id, ID, required: true
    end

    def ai_batch_job(id:)
      return nil unless context[:current_user]&.admin?

      AiBatchJob.find_by(id: id)
    end

    # -------------------------------------------------------------------------
    # C2PA / Content Provenance (admin only)
    # -------------------------------------------------------------------------

    field :c2pa_configuration, Types::C2paConfigurationType, null: false do
      description "The organisation's C2PA policy configuration (admin only)"
    end

    def c2pa_configuration
      return nil unless context[:current_user]&.admin?

      C2paConfiguration.current
    end

    field :asset_provenance_records, [ Types::AssetProvenanceRecordType ], null: false do
      description "List C2PA provenance records (admin only)"
      argument :status,      String,  required: false, description: "Filter by manifest_status"
      argument :ai_modified, Boolean, required: false, description: "Filter to AI-modified assets only"
      argument :limit,       Integer, required: false, default_value: 25
    end

    def asset_provenance_records(status: nil, ai_modified: nil, limit: 25)
      return [] unless context[:current_user]&.admin?

      scope = AssetProvenanceRecord.includes(:asset).recent.limit(limit.to_i.clamp(1, 100))
      scope = scope.where(manifest_status: status)  if status.present?
      scope = scope.where(is_ai_modified: true)     if ai_modified
      scope
    end

    field :asset_provenance_record, Types::AssetProvenanceRecordType, null: true do
      description "Find a C2PA provenance record by ID (admin only)"
      argument :id, ID, required: true
    end

    def asset_provenance_record(id:)
      return nil unless context[:current_user]&.admin?

      AssetProvenanceRecord.find_by(id: id)
    end

    # -------------------------------------------------------------------------
    # Style & Model Hub (admin only)
    # -------------------------------------------------------------------------

    field :ai_model_configs, [ Types::AiModelConfigType ], null: false do
      description "List registered AI model configs (admin only)"
      argument :capability, String,  required: false, description: "Filter by capability"
      argument :enabled,    Boolean, required: false, description: "Filter by enabled state"
    end

    def ai_model_configs(capability: nil, enabled: nil)
      return [] unless context[:current_user]&.admin?

      scope = AiModelConfig.order(capability: :asc, name: :asc)
      scope = scope.where(capability: capability) if capability.present?
      scope = scope.where(enabled: enabled)       unless enabled.nil?
      scope
    end

    field :ai_model_config, Types::AiModelConfigType, null: true do
      description "Find a single AI model config by ID (admin only)"
      argument :id, ID, required: true
    end

    def ai_model_config(id:)
      return nil unless context[:current_user]&.admin?

      AiModelConfig.find_by(id: id)
    end

    field :style_presets, [ Types::StylePresetType ], null: false do
      description "List style presets (admin only)"
      argument :active, Boolean, required: false, description: "Filter by active state"
    end

    def style_presets(active: nil)
      return [] unless context[:current_user]&.admin?

      scope = StylePreset.includes(:created_by).recent
      scope = scope.where(active: active) unless active.nil?
      scope
    end

    field :style_preset, Types::StylePresetType, null: true do
      description "Find a single style preset by ID (admin only)"
      argument :id, ID, required: true
    end

    def style_preset(id:)
      return nil unless context[:current_user]&.admin?

      StylePreset.find_by(id: id)
    end

    # -------------------------------------------------------------------------
    # Users (admin only)
    # -------------------------------------------------------------------------

    field :users, [ Types::UserType ], null: false do
      description "List all DAM users (admin only)"
    end

    def users
      return [] unless context[:current_user]&.admin?
      User.includes(:user_groups, :preference).order(created_at: :desc)
    end

    field :user, Types::UserType, null: true do
      description "Fetch a single DAM user by ID (admin only)"
      argument :id, ID, required: true
    end

    def user(id:)
      return nil unless context[:current_user]&.admin?
      User.find_by(id: id)
    end

    # -------------------------------------------------------------------------
    # User Groups (admin only)
    # -------------------------------------------------------------------------

    field :user_groups, [ Types::UserGroupType ], null: false do
      description "List all user groups (admin only)"
    end

    def user_groups
      return [] unless context[:current_user]&.admin?
      UserGroup.includes(:users, :child_groups).order(name: :asc)
    end

    field :user_group, Types::UserGroupType, null: true do
      description "Fetch a single user group by ID (admin only)"
      argument :id, ID, required: true
    end

    def user_group(id:)
      return nil unless context[:current_user]&.admin?
      UserGroup.find_by(id: id)
    end

    # -------------------------------------------------------------------------
    # Duplicate Manager
    # -------------------------------------------------------------------------

    field :duplicate_groups, Types::DuplicateGroupType.connection_type, null: false do
      description "Paginated list of duplicate asset groups."
      argument :status, String, required: false, default_value: "pending",
               description: "Filter by status: pending (default), resolved, dismissed, all."
    end

    def duplicate_groups(status: "pending")
      scope = case status
      when "resolved"  then DuplicateGroup.resolved
      when "dismissed" then DuplicateGroup.dismissed
      when "all"       then DuplicateGroup.all
      else                  DuplicateGroup.pending
      end
      scope.order(created_at: :desc).limit(DuplicateGroup::DISPLAY_LIMIT)
    end

    field :duplicate_group, Types::DuplicateGroupType, null: true do
      description "Fetch a single duplicate group by ID."
      argument :id, String, required: true
    end

    def duplicate_group(id:)
      DuplicateGroup.find_by(id: id)
    end

    field :duplicate_manager_stats, Types::JsonType, null: false do
      description "Counts of duplicate groups by status."
    end

    def duplicate_manager_stats
      {
        pending:   DuplicateGroup.pending.count,
        resolved:  DuplicateGroup.resolved.count,
        dismissed: DuplicateGroup.dismissed.count,
        total:     DuplicateGroup.count,
      }
    end

    # Returns the current state of the background repository scan.
    #
    # +scan_status+ values: idle | queued | running | completed | failed
    field :duplicate_manager_scan_status, Types::JsonType, null: false do
      description "Current status and progress of the background repository duplicate scan."
    end

    def duplicate_manager_scan_status
      raw_status   = Setting.get("duplicate_manager_scan_status")
      raw_progress = Setting.get("duplicate_manager_scan_progress")
      last_scan_at = Setting.get("duplicate_manager_last_scan_at")

      progress = raw_progress.is_a?(Hash) ? raw_progress : {}

      {
        scan_status:   raw_status.to_s.presence || "idle",
        scan_progress: progress,
        last_scan_at:  last_scan_at,
      }
    end

    # Returns aggregate statistics for the Recycle Bin.
    #
    # @return [Types::BinStatsType]
    field :bin_stats, Types::BinStatsType, null: false do
      description "Aggregate statistics for the Recycle Bin (total items, storage used, retention policy)."
    end

    def bin_stats
      trashed_assets  = Asset.trashed.includes(:active_version)
      trashed_folders = Folder.trashed

      total_size = trashed_assets.sum do |a|
        (a.active_version&.properties&.dig("size") || a.properties&.dig("size") || 0).to_i
      end

      oldest_asset  = trashed_assets.minimum(:deleted_at)
      oldest_folder = trashed_folders.minimum(:deleted_at)
      oldest_at     = [ oldest_asset, oldest_folder ].compact.min

      {
        total_items:       trashed_assets.count + trashed_folders.count,
        total_assets:      trashed_assets.count,
        total_folders:     trashed_folders.count,
        total_size_bytes:  total_size,
        retention_days:    Api::V1::BinController::DEFAULT_RETENTION_DAYS,
        oldest_deleted_at: oldest_at,
      }
    end

    # Returns the current Recycle Bin purge retention policy.
    #
    # @return [Types::BinRetentionPolicyType]
    field :bin_retention_policy, Types::BinRetentionPolicyType, null: false do
      description "The current automatic purge retention policy for the Recycle Bin."
    end

    def bin_retention_policy
      {
        retention_days:    (Setting.get("bin_retention_days")    || BinPurgeWorker::DEFAULT_RETENTION_DAYS).to_i,
        workflow_behavior: (Setting.get("bin_workflow_behavior") || BinPurgeWorker::DEFAULT_WORKFLOW_BEHAVIOR).to_s,
        batch_size:        (Setting.get("bin_purge_batch_size")  || BinPurgeWorker::DEFAULT_BATCH_SIZE).to_i,
        notify_admins:     Setting.get("bin_purge_notify_admins").nil? ? BinPurgeWorker::DEFAULT_NOTIFY_ADMINS : (Setting.get("bin_purge_notify_admins").to_s == "true"),
        next_scheduled_at: nil,
      }
    end

    # Returns the current bin purge job status and last-run results.
    #
    # @return [Types::BinPurgeStatusType]
    field :bin_purge_status, Types::BinPurgeStatusType, null: false do
      description "Current background purge job status and results of the last run."
    end

    def bin_purge_status
      raw_results  = Setting.get("bin_purge_last_results")
      triggered_by = Setting.get("bin_purge_triggered_by")
      {
        status:       Setting.get(BinPurgeWorker::LOCK_KEY).to_s.presence || "idle",
        last_ran_at:  Setting.get("bin_purge_last_ran_at"),
        started_at:   Setting.get("bin_purge_started_at"),
        triggered_by: triggered_by.is_a?(Hash) ? triggered_by : {},
        last_results: raw_results.is_a?(Hash) ? raw_results : {},
        policy:       bin_retention_policy,
      }
    end

    # AI-assisted bin cleanup suggestions (admin only).
    #
    # Heuristic-ranked until the Capri AI Gateway is integrated.
    #
    # @param limit [Integer] max suggestions to return (1–50, default 20)
    # @return [Array<Types::BinAiSuggestionType>]
    field :bin_ai_suggestions, [ Types::BinAiSuggestionType ], null: false do
      description "AI-assisted suggestions for assets that are safe to permanently purge (admin only)."
      argument :limit, Integer, required: false, default_value: 20
    end

    def bin_ai_suggestions(limit: 20)
      user = context[:current_user]
      raise GraphQL::ExecutionError, "Administrator privileges required." unless user&.admin?

      limit     = limit.to_i.clamp(1, 50)
      threshold = (Setting.get("bin_retention_days") || BinPurgeWorker::DEFAULT_RETENTION_DAYS).to_i.days.ago

      candidates = Asset.trashed
                        .where("deleted_at < ?", threshold)
                        .includes(:collection_assets, :workflow_instances, :active_version)
                        .order("deleted_at ASC")
                        .limit(limit * 3)

      suggestions = candidates.map do |a|
        age_days   = ((Time.current - a.deleted_at) / 86_400).to_i
        has_coll   = a.collection_assets.any?
        has_wf     = a.workflow_instances.any? { |wi| BinPurgeService::ACTIVE_WORKFLOW_STATUSES.include?(wi.status.to_s) }
        props      = a.active_version&.properties || a.properties
        size_bytes = (props["size"] || 0).to_i

        {
          id:                  a.id,
          title:               a.title,
          deleted_at:          a.deleted_at,
          age_days:            age_days,
          size_bytes:          size_bytes,
          size_human:          ActiveSupport::NumberHelper.number_to_human_size(size_bytes),
          has_collection_pin:  has_coll,
          has_active_workflow: has_wf,
          heuristic_score:     bin_heuristic_score(age_days, size_bytes, has_coll, has_wf),
          ai_risk_score:       nil,
          ai_reason:           nil,
          ai_tags:             [],
        }
      end

      suggestions
        .reject { |s| s[:has_active_workflow] }
        .sort_by { |s| -s[:heuristic_score] }
        .first(limit)
    end

    # ── Workflow queries ─────────────────────────────────────────────────────

    # All steps for a given workflow blueprint.
    #
    # @param workflow_id [ID] the Workflow's database ID
    # @return [Array<Types::WorkflowStepType>]
    field :workflow_steps, [ Types::WorkflowStepType ], null: false do
      description "Ordered list of steps in a workflow blueprint (authenticated users only)."
      argument :workflow_id, ID, required: true
    end

    def workflow_steps(workflow_id:)
      raise GraphQL::ExecutionError, "Authentication required." unless context[:current_user]

      workflow = Workflow.find_by(id: workflow_id)
      return [] unless workflow

      workflow.workflow_steps.order(:position)
    end

    # Active and recent workflow instances for a given asset.
    #
    # @param asset_id [ID] the Asset's database ID
    # @param limit    [Integer] max results (1–50, default 10)
    # @return [Array<Types::WorkflowInstanceType>]
    field :workflow_instances, [ Types::WorkflowInstanceType ], null: false do
      description "Workflow execution records for an asset (authenticated users only)."
      argument :asset_id, ID, required: true
      argument :limit,    Integer, required: false, default_value: 10
    end

    def workflow_instances(asset_id:, limit: 10)
      raise GraphQL::ExecutionError, "Authentication required." unless context[:current_user]

      Asset.find_by(id: asset_id)
           &.workflow_instances
           &.order(created_at: :desc)
           &.limit(limit.to_i.clamp(1, 50)) || []
    end

    private

    # Rule-based safe-to-delete score (0–100) used until AI gateway is live.
    def bin_heuristic_score(age_days, size_bytes, has_collection_pin, has_active_workflow)
      return 0 if has_active_workflow

      age_score  = [ age_days.to_f / 365 * 40, 40 ].min
      size_score = [ Math.log10([ size_bytes, 1 ].max) * 4, 30 ].min
      pin_score  = has_collection_pin ? 0 : 20
      (age_score + size_score + pin_score + 10).round
    end
  end
end
