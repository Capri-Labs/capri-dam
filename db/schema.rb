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

ActiveRecord::Schema[8.1].define(version: 2026_06_03_084017) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"
  enable_extension "vector"

  create_table "asset_embeddings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "asset_id", null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1536, null: false
    t.string "model_name", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_asset_embeddings_on_asset_id", unique: true
    t.index ["embedding"], name: "index_asset_embeddings_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
  end

  create_table "assets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.uuid "folder_id"
    t.jsonb "properties", default: {}, null: false
    t.string "status", default: "draft"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "uuid", null: false
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
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id"
    t.index ["auditable_type", "auditable_id", "ip_address", "user_id"], name: "idx_audit_logs_polymorphic_ip_user"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "collection_assets", force: :cascade do |t|
    t.uuid "asset_id", null: false
    t.bigint "collection_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 0
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["asset_id"], name: "index_collection_assets_on_asset_id"
    t.index ["collection_id", "asset_id"], name: "index_collection_assets_on_collection_id_and_asset_id", unique: true
    t.index ["collection_id"], name: "index_collection_assets_on_collection_id"
  end

  create_table "collections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
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
    t.boolean "approval_flow", default: false, null: false
    t.datetime "created_at", null: false
    t.boolean "delete_access", default: false, null: false
    t.boolean "explicit_deny", default: false, null: false
    t.uuid "folder_id", null: false
    t.boolean "manage_access", default: false, null: false
    t.boolean "read_access", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_group_id", null: false
    t.boolean "write_access", default: false, null: false
    t.index ["folder_id", "user_group_id"], name: "index_folder_policies_on_folder_id_and_user_group_id", unique: true
    t.index ["folder_id"], name: "index_folder_policies_on_folder_id"
    t.index ["user_group_id"], name: "index_folder_policies_on_user_group_id"
  end

  create_table "folders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
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
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "processed_count", default: 0
    t.string "source_type", null: false
    t.integer "status", default: 0, null: false
    t.integer "total_count", default: 0
    t.datetime "updated_at", null: false
    t.integer "user_id"
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
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_user_groups_on_name", unique: true
  end

  create_table "user_preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "receive_mention_emails", default: true, null: false
    t.boolean "receive_workflow_emails", default: true, null: false
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

  add_foreign_key "asset_embeddings", "assets"
  add_foreign_key "assets", "folders"
  add_foreign_key "assets", "users"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "collection_assets", "assets"
  add_foreign_key "collection_assets", "collections"
  add_foreign_key "email_deliveries", "email_templates"
  add_foreign_key "folder_policies", "folders"
  add_foreign_key "folder_policies", "user_groups"
  add_foreign_key "folders", "folders", column: "parent_id"
  add_foreign_key "folders", "users"
  add_foreign_key "in_app_notifications", "users"
  add_foreign_key "in_app_notifications", "users", column: "actor_id"
  add_foreign_key "ingestion_items", "ingestion_batches"
  add_foreign_key "notifications", "users"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "renditions", "assets"
  add_foreign_key "renditions", "storage_backends"
  add_foreign_key "report_snapshots", "report_definitions"
  add_foreign_key "user_group_memberships", "user_groups"
  add_foreign_key "user_group_memberships", "users"
  add_foreign_key "user_preferences", "users"
  add_foreign_key "workflow_instances", "assets"
  add_foreign_key "workflow_instances", "workflows"
  add_foreign_key "workflow_steps", "workflows"
  add_foreign_key "workflow_tasks", "users"
  add_foreign_key "workflow_tasks", "workflow_instances"
  add_foreign_key "workflow_tasks", "workflow_steps"
end
