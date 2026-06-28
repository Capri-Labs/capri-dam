# frozen_string_literal: true

# Creates the two tables that power the Style & Model Hub screen (/ai/models/hub):
#
#   ai_model_configs — registry of AI model endpoints used by the gateway
#   style_presets    — brand/style profiles pushed to the gateway for generation tasks
#
# Both are fully reversible via the +change+ method.
class CreateAiModelConfigsAndStylePresets < ActiveRecord::Migration[8.1]
  def change
    # ------------------------------------------------------------------
    # ai_model_configs
    # ------------------------------------------------------------------
    # Tracks every AI model registered for use with the Capri DAM gateway.
    # One row per model endpoint; capability determines how the gateway uses it
    # (embedding / generation / vision / style_transfer / audio).
    create_table :ai_model_configs do |t|
      t.string  :name,             null: false
      t.string  :provider,         null: false, default: "openai"
      t.string  :model_id,         null: false
      t.string  :capability,       null: false, default: "generation"
      t.boolean :enabled,          null: false, default: true
      t.boolean :is_default,       null: false, default: false
      t.jsonb   :config_params,    null: false, default: {}
      # Gateway-reported health
      t.string   :health_status,       null: false, default: "unknown"
      t.integer  :health_latency_ms
      t.datetime :last_health_check_at
      t.text     :error_message
      # Freeform metadata (e.g. context_window, pricing_tier)
      t.jsonb    :metadata,        null: false, default: {}

      t.timestamps
    end

    add_index :ai_model_configs, :provider
    add_index :ai_model_configs, :capability
    add_index :ai_model_configs, :enabled
    add_index :ai_model_configs, :is_default
    add_index :ai_model_configs, :health_status
    # Enforce at most one default per capability at the DB level
    add_index :ai_model_configs,
              [ :capability, :is_default ],
              unique: true,
              where:  "is_default = TRUE",
              name:   "index_ai_model_configs_one_default_per_capability"

    # ------------------------------------------------------------------
    # style_presets
    # ------------------------------------------------------------------
    # Named brand/style profiles (colour palettes, tone, aspect ratio, …).
    # Pushed to the gateway via StylePresetSyncWorker so generation tasks
    # can reference them by slug.
    create_table :style_presets do |t|
      t.string  :name,         null: false
      t.string  :slug,         null: false
      t.text    :description
      t.boolean :active,       null: false, default: true
      t.boolean :is_default,   null: false, default: false
      t.jsonb   :style_params, null: false, default: {}
      # Gateway sync state
      t.string   :gateway_ref
      t.datetime :synced_at
      t.bigint   :created_by_id

      t.timestamps
    end

    add_index :style_presets, :slug,         unique: true
    add_index :style_presets, :active
    add_index :style_presets, :is_default
    add_index :style_presets, :created_by_id

    add_foreign_key :style_presets, :users, column: :created_by_id, on_delete: :nullify
  end
end
