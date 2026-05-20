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

ActiveRecord::Schema[8.1].define(version: 2026_05_20_075119) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

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
    t.string "name", null: false
    t.uuid "parent_id"
    t.string "path"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["parent_id"], name: "index_folders_on_parent_id"
    t.index ["path"], name: "index_folders_on_path"
    t.index ["slug"], name: "index_folders_on_slug"
    t.index ["user_id"], name: "index_folders_on_user_id"
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

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true
    t.boolean "admin", default: false, null: false
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "department"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
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
    t.string "username", null: false
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
    t.datetime "created_at", null: false
    t.integer "current_step_id"
    t.integer "last_action_by_id"
    t.string "status"
    t.datetime "updated_at", null: false
    t.bigint "workflow_id", null: false
    t.index ["asset_id"], name: "index_workflow_instances_on_asset_id"
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

  create_table "workflows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.text "description"
    t.string "fallback_assignee_id"
    t.string "fallback_assignee_type"
    t.jsonb "metadata"
    t.string "name"
    t.integer "status"
    t.string "trigger_type"
    t.datetime "updated_at", null: false
    t.integer "updated_by_id"
  end

  add_foreign_key "assets", "folders"
  add_foreign_key "assets", "users"
  add_foreign_key "email_deliveries", "email_templates"
  add_foreign_key "folder_policies", "folders"
  add_foreign_key "folder_policies", "user_groups"
  add_foreign_key "folders", "folders", column: "parent_id"
  add_foreign_key "folders", "users"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "renditions", "assets"
  add_foreign_key "renditions", "storage_backends"
  add_foreign_key "user_group_memberships", "user_groups"
  add_foreign_key "user_group_memberships", "users"
  add_foreign_key "workflow_instances", "assets"
  add_foreign_key "workflow_instances", "workflows"
  add_foreign_key "workflow_steps", "workflows"
end
