# frozen_string_literal: true

# Singleton configuration table for the organisation's C2PA / Content Provenance
# policy settings.  Uses {C2paConfiguration.current} (first_or_create! pattern).
#
# Broadcasting: every save publishes a `c2pa.config.updated` event to the
# `ai_gateway_events` Redis channel so the gateway hot-swaps parameters.
class CreateC2paConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :c2pa_configurations do |t|
      # ── Gateway toggle ─────────────────────────────────────────────────────
      t.boolean :gateway_c2pa_enabled,   null: false, default: false

      # ── Ingest hooks ────────────────────────────────────────────────────────
      t.boolean :auto_verify_on_ingest,  null: false, default: false
      t.boolean :auto_sign_on_ingest,    null: false, default: false
      t.boolean :require_c2pa_on_import, null: false, default: false

      # ── AI disclosure policy ────────────────────────────────────────────────
      t.boolean :ai_disclosure_required, null: false, default: true

      # ── Signing identity ────────────────────────────────────────────────────
      t.string  :signing_issuer_name
      t.string  :signing_org

      # ── Trust-store certificate URLs (array of strings) ─────────────────────
      t.jsonb   :trust_store_urls,        null: false, default: []

      # ── Verification behaviour: lenient | strict ────────────────────────────
      t.string  :verification_strictness, null: false, default: "lenient"

      # ── Free-text governance notes ──────────────────────────────────────────
      t.text    :policy_notes

      t.timestamps
    end
  end
end

