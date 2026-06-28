# frozen_string_literal: true

# Per-asset C2PA manifest and AI-provenance tracking record.
#
# One row per asset (UNIQUE constraint on +asset_id+).  Created lazily the
# first time the AI Gateway analyses an asset, or upfront as a placeholder
# when {AssetProvenanceWorker} fires an individual verification request.
#
# == Manifest lifecycle
#
#   unchecked → (gateway verifies)
#                 → verified       # valid manifest, all sigs check out
#                 → ai_generated   # valid manifest, asset is AI-generated
#                 → ai_modified    # valid manifest, AI tool was used post-creation
#                 → missing        # no C2PA data found in the file
#                 → invalid        # manifest present but signature verification failed
#                 → error          # gateway processing error
#             → (gateway signs)
#                 → signed         # DAM identity embedded via c2pa.sign
#
# == Bulk upsert
#
# Records are batch-upserted by {Api::V1::AssetProvenanceRecordsController#bulk_upsert}
# which the AI Gateway calls after every processed batch.
class CreateAssetProvenanceRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :asset_provenance_records do |t|
      # UUID FK → assets.id  (assets table uses UUID primary key)
      t.uuid   :asset_id, null: false

      # Overall C2PA manifest state
      t.string :manifest_status, null: false, default: "unchecked"

      # Parsed C2PA manifest payload returned by the gateway
      t.jsonb  :manifest_data,   null: false, default: {}

      # Which tool generated the C2PA claim (e.g. "Adobe Photoshop 25.0")
      t.string :claim_generator

      # AI-provenance flags
      t.boolean :is_ai_modified,  null: false, default: false
      t.jsonb   :ai_tools_used,   null: false, default: []

      # Verification timestamps
      t.datetime :verified_at

      # Signing metadata
      t.datetime :signed_at
      t.string   :signer_name
      t.string   :signer_cert_fingerprint

      # Error detail when manifest_status == "error"
      t.text     :error_detail

      t.timestamps
    end

    add_index :asset_provenance_records, :asset_id,        unique: true
    add_index :asset_provenance_records, :manifest_status
    add_index :asset_provenance_records, :is_ai_modified
    add_index :asset_provenance_records, :verified_at

    add_foreign_key :asset_provenance_records, :assets, column: :asset_id, primary_key: :id
  end
end

