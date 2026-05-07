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

ActiveRecord::Schema[8.1].define(version: 2026_05_07_150008) do
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

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name", null: false
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "assets", "folders"
  add_foreign_key "assets", "users"
  add_foreign_key "folders", "folders", column: "parent_id"
  add_foreign_key "folders", "users"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "renditions", "assets"
  add_foreign_key "renditions", "storage_backends"
end
