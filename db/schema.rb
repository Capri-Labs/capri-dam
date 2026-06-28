# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_28_110000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"
  enable_extension "vector"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_executions", force: :cascade do |t|
    t.bigint "agent_workflow_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.jsonb "output", default: {}, null: false
    t.datetime "started_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "status", default: "running", null: false
    t.text "summary"
    t.jsonb "trigger_payload", default: {}, null: false
    t.string "trigger_type", default: "event", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_workflow_id"], name: "index_agent_executions_on_agent_workflow_id"
    t.index ["started_at"], name: "index_agent_executions_on_started_at"
    t.index ["status"], name: "index_agent_executions_on_status"
  end

  create_table "agent_workflows", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.string "agent_model", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "description"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.jsonb "tools_enabled", default: [], null: false
    t.string "trigger_event", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_agent_workflows_on_active"
    t.index ["created_by_id"], name: "index_agent_workflows_on_created_by_id"
    t.index ["trigger_event"], name: "index_agent_workflows_on_trigger_event"
  end

  create_table "ai_batch_jobs", force: :cascade do |t|
    t.datetime "completed_at"
    t.integer "concurrency", default: 25, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "error_message"
    t.integer "failed_count", default: 0, null: false
    t.jsonb "options", default: {}, null: false
    t.integer "processed_count", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.integer "succeeded_count", default: 0, null: false
    t.string "target_scope", null: false
    t.string "task_type", null: false
    t.integer "total_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_ai_batch_jobs_on_created_at"
    t.index ["created_by_id"], name: "index_ai_batch_jobs_on_created_by_id"
    t.index ["status"], name: "index_ai_batch_jobs_on_status"
    t.index ["task_type"], name: "index_ai_batch_jobs_on_task_type"
  end

  create_table "ai_configurations", force: :cascade do |t|
    t.string "active_provider"
    t.datetime "created_at", null: false
    t.decimal "current_spend_usd"
    t.string "embedding_model"
    t.boolean "fallback_to_local"
    t.string "generation_model"
    t.decimal "monthly_budget_usd"
    t.text "system_prompt"
    t.datetime "updated_at", null: false
  end

  create_table "asset_embeddings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "asset_id", null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1536, null: false
    t.string "model_name", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_asset_embeddings_on_asset_id", unique: true
    t.index ["embedding"], name: "index_asset_embeddings_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
  end

  create_table "asset_versions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action_type", default: "initial_upload"
    t.uuid "asset_id", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.jsonb "properties", default: {}
    t.datetime "updated_at", null: false
    t.integer "version_number", default: 1, null: false
    t.index ["asset_id", "version_number"], name: "index_asset_versions_on_asset_id_and_version_number", unique: true
    t.index ["asset_id"], name: "index_asset_versions_on_asset_id"
    t.index ["created_by_id"], name: "index_asset_versions_on_created_by_id"
  end

  create_table "assets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "active_version_id"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.uuid "folder_id"
    t.jsonb "properties", default: {}, null: false
    t.string "status", default: "draft"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "uuid", null: false
    t.index ["active_version_id"], name: "index_assets_on_active_version_id"
    t.index ["deleted_at"], name: "index_assets_on_deleted_at"
    t.index ["folder_id"], name: "index_assets_on_folder_id"
    t.index ["properties"], name: "index_assets_on_properties", using: :gin
    t.index ["user_id"], name: "index_assets_on_user_id"
    t.index ["uuid"], name: "index_assets_on_uuid", unique: true
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action"
    t.integer "auditable_id"
    t.string "auditable_type"
    t.jsonb "changes_data"
    t.datetime "created_at", null: false
    t.boolean "impersonated", default: false, null: false
    t.string "ip_address"
    t.bigint "true_user_id"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id"
    t.index ["auditable_type", "auditable_id", "ip_address", "user_id"], name: "idx_audit_logs_polymorphic_ip_user"
    t.index ["true_user_id"], name: "index_audit_logs_on_true_user_id"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "cdn_configurations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_active"
    t.string "provider"
    t.text "settings"
    t.datetime "updated_at", null: false
  end

  create_table "collection_assets", force: :cascade do |t|
    t.uuid "asset_id", null: false
    t.bigint "collection_id", null: false
    t.bigint "collection_rule_id"
    t.datetime "created_at", null: false
    t.boolean "pinned", default: false, null: false
    t.integer "position", default: 0
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["asset_id"], name: "index_collection_assets_on_asset_id"
    t.index ["collection_id", "asset_id"], name: "index_collection_assets_on_collection_id_and_asset_id", unique: true
    t.index ["collection_id"], name: "index_collection_assets_on_collection_id"
    t.index ["collection_rule_id"], name: "index_collection_assets_on_collection_rule_id"
  end

  create_table "collection_rules", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "collection_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata_filters", default: {}
    t.text "semantic_prompt", null: false
    t.decimal "similarity_threshold", precision: 4, scale: 3, default: "0.8"
    t.datetime "updated_at", null: false
    t.index ["collection_id"], name: "index_collection_rules_on_collection_id"
    t.index ["metadata_filters"], name: "index_collection_rules_on_metadata_filters", using: :gin
  end

  create_table "collections", force: :cascade do |t|
    t.string "collection_type", default: "manual", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.datetime "expires_at"
    t.string "name"
    t.jsonb "properties"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.uuid "uuid"
    t.index ["slug"], name: "index_collections_on_slug", unique: true
    t.index ["uuid"], name: "index_collections_on_uuid", unique: true
  end

  create_table "daily_metrics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}
    t.date "metric_date", null: false
    t.string "metric_name", null: false
    t.integer "metric_value", default: 0
    t.datetime "updated_at", null: false
    t.index ["metric_date", "metric_name"], name: "index_daily_metrics_on_metric_date_and_metric_name", unique: true
  end

  create_table "duplicate_group_assets", force: :cascade do |t|
    t.uuid "asset_id", null: false
    t.datetime "created_at", null: false
    t.uuid "duplicate_group_id", null: false
    t.boolean "is_original", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_duplicate_group_assets_on_asset_id"
    t.index ["duplicate_group_id", "asset_id"], name: "idx_dup_group_assets_unique", unique: true
    t.index ["duplicate_group_id"], name: "index_duplicate_group_assets_on_duplicate_group_id"
  end

  create_table "duplicate_groups", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "checksum", null: false
    t.datetime "created_at", null: false
    t.string "resolution_action"
    t.datetime "resolved_at"
    t.bigint "resolved_by_id"
    t.string "status", default: "pending", null: false
    t.integer "total_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["checksum"], name: "index_duplicate_groups_on_checksum", unique: true
    t.index ["resolved_by_id"], name: "index_duplicate_groups_on_resolved_by_id"
    t.index ["status"], name: "index_duplicate_groups_on_status"
  end

  create_table "email_deliveries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "email_template_id", null: false
    t.text "error_log"
    t.jsonb "payload", default: {}, null: false
    t.string "recipient_email", null: false
    t.integer "retry_count", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["email_template_id"], name: "index_email_deliveries_on_email_template_id"
    t.index ["payload"], name: "index_email_deliveries_on_payload", using: :gin
    t.index ["recipient_email"], name: "index_email_deliveries_on_recipient_email"
    t.index ["status"], name: "index_email_deliveries_on_status"
  end

  create_table "email_templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "event_trigger", null: false
    t.text "html_body"
    t.string "name", null: false
    t.string "subject", null: false
    t.text "text_body"
    t.datetime "updated_at", null: false
    t.index ["event_trigger"], name: "index_email_templates_on_event_trigger", unique: true
  end

  create_table "folder_policies", force: :cascade do |t|
    t.boolean "create_access", default: false, null: false
    t.datetime "created_at", null: false
    t.boolean "delete_access", default: false, null: false
    t.boolean "explicit_deny", default: false, null: false
    t.uuid "folder_id", null: false
    t.boolean "manage_access", default: false, null: false
    t.boolean "modify_access", default: false, null: false
    t.boolean "read_access", default: false, null: false
    t.boolean "replicate_access", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_group_id", null: false
    t.index ["folder_id", "user_group_id"], name: "index_folder_policies_on_folder_id_and_user_group_id", unique: true
    t.index ["folder_id"], name: "index_folder_policies_on_folder_id"
    t.index ["user_group_id"], name: "index_folder_policies_on_user_group_id"
  end

  create_table "folders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "name", null: false
    t.uuid "parent_id"
    t.string "path"
    t.jsonb "properties", default: {}
    t.string "slug"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["deleted_at"], name: "index_folders_on_deleted_at"
    t.index ["parent_id"], name: "index_folders_on_parent_id"
    t.index ["path"], name: "index_folders_on_path"
    t.index ["slug"], name: "index_folders_on_slug"
    t.index ["user_id"], name: "index_folders_on_user_id"
    t.index ["uuid"], name: "index_folders_on_uuid", unique: true
  end

  create_table "image_profile_folder_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "folder_id", null: false
    t.bigint "image_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["folder_id"], name: "index_image_profile_folder_assignments_on_folder_id"
    t.index ["image_profile_id", "folder_id"], name: "idx_image_profile_folder_assignments_unique", unique: true
    t.index ["image_profile_id"], name: "index_image_profile_folder_assignments_on_image_profile_id"
  end

  create_table "image_profiles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "crop_type", default: "none", null: false
    t.datetime "deleted_at"
    t.string "name", null: false
    t.boolean "responsive_crop_enabled", default: false, null: false
    t.jsonb "responsive_crops", default: [], null: false
    t.boolean "swatch_enabled", default: false, null: false
    t.integer "swatch_height", default: 100
    t.integer "swatch_width", default: 100
    t.jsonb "unsharp_mask", default: {"amount" => 1.75, "radius" => 0.2, "threshold" => 2}, null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_image_profiles_on_deleted_at"
    t.index ["name"], name: "index_image_profiles_on_name"
  end

  create_table "in_app_notifications", force: :cascade do |t|
    t.string "action_type", null: false
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.string "message", null: false
    t.bigint "notifiable_id", null: false
    t.string "notifiable_type", null: false
    t.datetime "read_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["actor_id"], name: "index_in_app_notifications_on_actor_id"
    t.index ["notifiable_type", "notifiable_id"], name: "index_in_app_notifications_on_notifiable"
    t.index ["user_id", "read_at"], name: "index_in_app_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_in_app_notifications_on_user_id"
  end

  create_table "ingestion_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "committed_count", default: 0
    t.datetime "completed_at"
    t.bigint "connector_id"
    t.datetime "created_at", null: false
    t.integer "duplicate_count", default: 0
    t.integer "error_count", default: 0
    t.bigint "initiated_by_id"
    t.string "name", null: false
    t.text "notes"
    t.integer "processed_count", default: 0
    t.bigint "report_snapshot_id"
    t.jsonb "source_credentials", default: {}
    t.string "source_type", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.integer "total_count", default: 0
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["connector_id"], name: "index_ingestion_batches_on_connector_id"
  end

  create_table "ingestion_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "clean_properties", default: {}
    t.datetime "created_at", null: false
    t.text "error_log"
    t.string "file_hash"
    t.bigint "file_size"
    t.uuid "ingestion_batch_id", null: false
    t.jsonb "legacy_metadata", default: {}
    t.string "original_filename", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["file_hash"], name: "index_ingestion_items_on_file_hash"
    t.index ["ingestion_batch_id"], name: "index_ingestion_items_on_ingestion_batch_id"
  end

  create_table "metadata_exports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "expires_at"
    t.integer "file_count", default: 0, null: false
    t.uuid "folder_id"
    t.boolean "include_subfolders", default: false, null: false
    t.string "name", null: false
    t.string "property_mode", default: "all", null: false
    t.datetime "scheduled_at"
    t.jsonb "selected_properties", default: [], null: false
    t.integer "status", default: 0, null: false
    t.integer "total_assets", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_metadata_exports_on_expires_at"
    t.index ["folder_id"], name: "index_metadata_exports_on_folder_id"
    t.index ["status"], name: "index_metadata_exports_on_status"
    t.index ["user_id"], name: "index_metadata_exports_on_user_id"
  end

  create_table "metadata_imports", force: :cascade do |t|
    t.string "asset_path_column", default: "asset_path", null: false
    t.integer "batch_size", default: 50, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "expires_at"
    t.integer "failure_count", default: 0, null: false
    t.string "field_separator", default: ",", null: false
    t.jsonb "ignored_columns", default: [], null: false
    t.boolean "launch_workflows", default: false, null: false
    t.string "multi_value_delimiter", default: "|", null: false
    t.string "name", null: false
    t.datetime "scheduled_at"
    t.integer "status", default: 0, null: false
    t.integer "success_count", default: 0, null: false
    t.integer "total_rows", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_metadata_imports_on_expires_at"
    t.index ["status"], name: "index_metadata_imports_on_status"
    t.index ["user_id"], name: "index_metadata_imports_on_user_id"
  end

  create_table "metadata_schema_folder_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "folder_id", null: false
    t.bigint "metadata_schema_id", null: false
    t.datetime "updated_at", null: false
    t.index ["folder_id"], name: "idx_schema_folder_on_folder_id"
    t.index ["metadata_schema_id", "folder_id"], name: "idx_schema_folder_unique", unique: true
  end

  create_table "metadata_schemas", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.boolean "is_builtin", default: false, null: false
    t.string "level", default: "root", null: false
    t.string "mime_segment"
    t.string "name", null: false
    t.bigint "parent_id"
    t.jsonb "properties", default: {}, null: false
    t.string "slug", null: false
    t.jsonb "tabs", default: [], null: false
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["deleted_at"], name: "index_metadata_schemas_on_deleted_at"
    t.index ["is_builtin"], name: "index_metadata_schemas_on_is_builtin"
    t.index ["level"], name: "index_metadata_schemas_on_level"
    t.index ["parent_id", "mime_segment"], name: "idx_metadata_schemas_parent_mime_unique", unique: true, where: "((deleted_at IS NULL) AND (mime_segment IS NOT NULL))"
    t.index ["parent_id"], name: "index_metadata_schemas_on_parent_id"
    t.index ["slug"], name: "index_metadata_schemas_on_slug", unique: true, where: "(deleted_at IS NULL)"
    t.index ["uuid"], name: "index_metadata_schemas_on_uuid", unique: true
  end

  create_table "notifications", force: :cascade do |t|
    t.string "action_url"
    t.datetime "created_at", null: false
    t.string "message"
    t.datetime "read_at"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.bigint "resource_owner_id", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: "", null: false
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in"
    t.string "previous_refresh_token", default: "", null: false
    t.string "refresh_token"
    t.bigint "resource_owner_id"
    t.datetime "revoked_at"
    t.string "scopes"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "owner_id"
    t.string "owner_type"
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.string "secret", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "personal_access_tokens", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "last_four", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.string "scopes", default: "read"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token_digest"], name: "index_personal_access_tokens_on_token_digest", unique: true
    t.index ["user_id", "active"], name: "index_personal_access_tokens_on_user_id_and_active"
    t.index ["user_id"], name: "index_personal_access_tokens_on_user_id"
  end

  create_table "quarantined_assets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "original_payload"
    t.text "rejection_reason"
    t.string "status"
    t.bigint "system_connector_id", null: false
    t.datetime "updated_at", null: false
    t.index ["system_connector_id"], name: "index_quarantined_assets_on_system_connector_id"
  end

  create_table "renditions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "asset_id", null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.bigint "file_size"
    t.integer "height"
    t.string "kind", null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "storage_backend_id", null: false
    t.string "storage_key", null: false
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["asset_id"], name: "index_renditions_on_asset_id"
    t.index ["storage_backend_id"], name: "index_renditions_on_storage_backend_id"
  end

  create_table "report_definitions", force: :cascade do |t|
    t.boolean "active"
    t.datetime "created_at", null: false
    t.string "name"
    t.jsonb "query_config"
    t.string "report_type"
    t.datetime "updated_at", null: false
  end

  create_table "report_snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "format", null: false
    t.jsonb "parameters", default: {}
    t.bigint "report_definition_id", null: false
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.index ["report_definition_id"], name: "index_report_snapshots_on_report_definition_id"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "storage_backends", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "provider_type", null: false
    t.datetime "updated_at", null: false
  end

  create_table "system_configurations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "data_type", default: "string", null: false
    t.string "description"
    t.datetime "expires_at"
    t.text "fallback_value"
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "updated_by_id"
    t.text "value", null: false
    t.index ["key"], name: "index_system_configurations_on_key", unique: true
    t.index ["updated_by_id"], name: "index_system_configurations_on_updated_by_id"
  end

  create_table "system_connectors", force: :cascade do |t|
    t.integer "assets_imported"
    t.string "auth_token"
    t.integer "concurrency_limit"
    t.datetime "created_at", null: false
    t.string "endpoint"
    t.datetime "last_sync"
    t.string "name"
    t.string "provider_type"
    t.integer "rps_limit"
    t.string "status"
    t.boolean "tdm_sanitation"
    t.datetime "updated_at", null: false
    t.string "webhook_secret"
  end

  create_table "transformation_presets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.jsonb "params"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_transformation_presets_on_slug"
  end

  create_table "user_group_closures", id: false, force: :cascade do |t|
    t.bigint "ancestor_id", null: false
    t.bigint "descendant_id", null: false
    t.integer "distance", null: false
    t.index ["ancestor_id", "descendant_id"], name: "idx_group_closures_pk", unique: true
    t.index ["descendant_id"], name: "index_user_group_closures_on_descendant_id"
  end

  create_table "user_group_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_group_id", null: false
    t.bigint "user_id", null: false
    t.index ["user_group_id"], name: "index_user_group_memberships_on_user_group_id"
    t.index ["user_id", "user_group_id"], name: "index_user_group_memberships_on_user_id_and_user_group_id", unique: true
    t.index ["user_id"], name: "index_user_group_memberships_on_user_id"
  end

  create_table "user_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.boolean "is_system", default: false, null: false
    t.string "name", null: false
    t.bigint "parent_id"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_user_groups_on_name", unique: true
    t.index ["parent_id"], name: "index_user_groups_on_parent_id"
    t.index ["slug"], name: "index_user_groups_on_slug", unique: true
  end

  create_table "user_impersonators", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "impersonator_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["impersonator_id"], name: "index_user_impersonators_on_impersonator_id"
    t.index ["user_id", "impersonator_id"], name: "index_user_impersonators_on_pair", unique: true
    t.index ["user_id"], name: "index_user_impersonators_on_user_id"
  end

  create_table "user_preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "language", default: "en", null: false
    t.boolean "receive_mention_emails", default: true, null: false
    t.boolean "receive_workflow_emails", default: true, null: false
    t.string "theme", default: "system", null: false
    t.string "timezone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_user_preferences_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true
    t.boolean "admin", default: false, null: false
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "department"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
    t.boolean "force_password_change", default: false
    t.string "last_name"
    t.string "name", null: false
    t.jsonb "preferences", default: {}
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", default: "viewer"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["active"], name: "index_users_on_active"
    t.index ["department"], name: "index_users_on_department"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["first_name"], name: "index_users_on_first_name"
    t.index ["last_name"], name: "index_users_on_last_name"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "video_encoding_presets", force: :cascade do |t|
    t.jsonb "advanced_params", default: {}, null: false
    t.integer "audio_bitrate_kbps", default: 128, null: false
    t.string "audio_codec", default: "he_aac", null: false
    t.integer "audio_sampling_rate"
    t.boolean "constant_bitrate", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "frame_rate_fps", default: 30, null: false
    t.string "h264_profile"
    t.integer "height", null: false
    t.boolean "keep_aspect_ratio", default: true, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.boolean "two_pass_encoding", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "video_bitrate_kbps", null: false
    t.string "video_format_codec", default: "h264", null: false, comment: "mp4 h.264 = h264"
    t.bigint "video_profile_id", null: false
    t.integer "width"
    t.index ["video_profile_id"], name: "index_video_encoding_presets_on_video_profile_id"
  end

  create_table "video_profile_folder_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "folder_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_profile_id", null: false
    t.index ["folder_id"], name: "index_video_profile_folder_assignments_on_folder_id"
    t.index ["video_profile_id", "folder_id"], name: "idx_video_profile_folder_assignments_unique", unique: true
    t.index ["video_profile_id"], name: "index_video_profile_folder_assignments_on_video_profile_id"
  end

  create_table "video_profiles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.boolean "encode_for_adaptive_streaming", default: true, null: false
    t.string "name", null: false
    t.jsonb "smart_crop_ratios", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_video_profiles_on_deleted_at"
    t.index ["name"], name: "index_video_profiles_on_name"
  end

  create_table "workflow_instances", force: :cascade do |t|
    t.uuid "asset_id", null: false
    t.jsonb "audit_log"
    t.jsonb "blueprint_snapshot", default: {}
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "current_step_id"
    t.integer "last_action_by_id"
    t.datetime "started_at"
    t.string "status"
    t.datetime "updated_at", null: false
    t.bigint "workflow_id", null: false
    t.index ["asset_id"], name: "index_workflow_instances_on_asset_id"
    t.index ["completed_at"], name: "index_workflow_instances_on_completed_at"
    t.index ["started_at"], name: "index_workflow_instances_on_started_at"
    t.index ["workflow_id"], name: "index_workflow_instances_on_workflow_id"
  end

  create_table "workflow_steps", force: :cascade do |t|
    t.integer "assignee_id"
    t.string "assignee_type"
    t.jsonb "configuration"
    t.datetime "created_at", null: false
    t.integer "deadline_days"
    t.text "description"
    t.string "logic"
    t.integer "position"
    t.string "step_type"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "updated_by_id"
    t.bigint "workflow_id", null: false
    t.index ["workflow_id"], name: "index_workflow_steps_on_workflow_id"
  end

  create_table "workflow_tasks", force: :cascade do |t|
    t.text "comment"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workflow_instance_id", null: false
    t.bigint "workflow_step_id", null: false
    t.index ["user_id", "status"], name: "index_workflow_tasks_on_user_id_and_status"
    t.index ["user_id"], name: "index_workflow_tasks_on_user_id"
    t.index ["workflow_instance_id"], name: "index_workflow_tasks_on_workflow_instance_id"
    t.index ["workflow_step_id"], name: "index_workflow_tasks_on_workflow_step_id"
  end

  create_table "workflows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.text "description"
    t.string "exclude_folder_ids", default: [], array: true
    t.string "fallback_assignee_id"
    t.string "fallback_assignee_type"
    t.string "folder_scope", default: "all"
    t.jsonb "graph_data", default: {}
    t.jsonb "metadata"
    t.string "name"
    t.integer "status"
    t.string "target_folder_ids", default: [], array: true
    t.string "trigger_type"
    t.datetime "updated_at", null: false
    t.integer "updated_by_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_executions", "agent_workflows"
  add_foreign_key "agent_workflows", "users", column: "created_by_id"
  add_foreign_key "ai_batch_jobs", "users", column: "created_by_id"
  add_foreign_key "asset_embeddings", "assets"
  add_foreign_key "asset_versions", "assets"
  add_foreign_key "asset_versions", "users", column: "created_by_id"
  add_foreign_key "assets", "asset_versions", column: "active_version_id"
  add_foreign_key "assets", "folders"
  add_foreign_key "assets", "users"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "collection_assets", "assets"
  add_foreign_key "collection_assets", "collection_rules"
  add_foreign_key "collection_assets", "collections"
  add_foreign_key "collection_rules", "collections"
  add_foreign_key "duplicate_group_assets", "assets"
  add_foreign_key "duplicate_group_assets", "duplicate_groups"
  add_foreign_key "duplicate_groups", "users", column: "resolved_by_id"
  add_foreign_key "email_deliveries", "email_templates"
  add_foreign_key "folder_policies", "folders"
  add_foreign_key "folder_policies", "user_groups"
  add_foreign_key "folders", "folders", column: "parent_id"
  add_foreign_key "folders", "users"
  add_foreign_key "image_profile_folder_assignments", "image_profiles"
  add_foreign_key "in_app_notifications", "users"
  add_foreign_key "in_app_notifications", "users", column: "actor_id"
  add_foreign_key "ingestion_batches", "system_connectors", column: "connector_id", on_delete: :nullify
  add_foreign_key "ingestion_items", "ingestion_batches"
  add_foreign_key "metadata_exports", "users"
  add_foreign_key "metadata_imports", "users"
  add_foreign_key "metadata_schema_folder_assignments", "metadata_schemas"
  add_foreign_key "metadata_schemas", "metadata_schemas", column: "parent_id"
  add_foreign_key "notifications", "users"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "quarantined_assets", "system_connectors"
  add_foreign_key "renditions", "assets"
  add_foreign_key "renditions", "storage_backends"
  add_foreign_key "report_snapshots", "report_definitions"
  add_foreign_key "user_group_memberships", "user_groups"
  add_foreign_key "user_group_memberships", "users"
  add_foreign_key "user_groups", "user_groups", column: "parent_id"
  add_foreign_key "user_impersonators", "users"
  add_foreign_key "user_impersonators", "users", column: "impersonator_id"
  add_foreign_key "user_preferences", "users"
  add_foreign_key "video_encoding_presets", "video_profiles"
  add_foreign_key "video_profile_folder_assignments", "video_profiles"
  add_foreign_key "workflow_instances", "assets"
  add_foreign_key "workflow_instances", "workflows"
  add_foreign_key "workflow_steps", "workflows"
  add_foreign_key "workflow_tasks", "users"
  add_foreign_key "workflow_tasks", "workflow_instances"
  add_foreign_key "workflow_tasks", "workflow_steps"
end
