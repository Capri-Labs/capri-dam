# frozen_string_literal: true

# Tracks the C2PA manifest and AI-provenance data for a single {Asset}.
#
# One record per asset (UNIQUE constraint on +asset_id+), created lazily when
# the AI Gateway first analyses an asset, or upfront as an "unchecked"
# placeholder by {AssetProvenanceWorker}.
#
# == Manifest status lifecycle
#
#   unchecked → (gateway verifies)
#               → verified       valid C2PA manifest; all signatures check out
#               → ai_generated   valid C2PA manifest; asset is AI-generated
#               → ai_modified    valid C2PA manifest; asset was AI-modified
#               → missing        no C2PA manifest found in the file
#               → invalid        manifest present but sig verification failed
#               → error          gateway processing error
#             → (gateway signs)
#               → signed         DAM identity successfully embedded
#
# == Bulk upsert
#
# Records are batch-upserted by
# {Api::V1::AssetProvenanceRecordsController#bulk_upsert}, which the AI
# Gateway calls after processing each batch of assets in a C2PA batch task.
#
# @see AssetProvenanceWorker
# @see C2paConfiguration
# @see Ai::BatchTaskRegistry
class AssetProvenanceRecord < ApplicationRecord
  MANIFEST_STATUSES = %w[
    unchecked verified ai_generated ai_modified missing invalid signed error
  ].freeze

  AI_STATUSES = %w[ai_generated ai_modified].freeze

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  # assets table uses UUID as primary key
  belongs_to :asset, primary_key: :id, foreign_key: :asset_id

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :manifest_status, presence: true, inclusion: { in: MANIFEST_STATUSES }
  validates :asset_id,        presence: true, uniqueness: true

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  scope :recent,       -> { order(updated_at: :desc) }
  scope :verified,     -> { where(manifest_status: "verified") }
  scope :ai_flagged,   -> { where(manifest_status: AI_STATUSES) }
  scope :ai_modified,  -> { where(is_ai_modified: true) }
  scope :missing,      -> { where(manifest_status: "missing") }
  scope :invalid_manifest, -> { where(manifest_status: "invalid") }
  scope :signed,       -> { where(manifest_status: "signed") }
  scope :unchecked,    -> { where(manifest_status: "unchecked") }
  scope :needs_review, -> { where(manifest_status: %w[missing invalid error]) }

  # ---------------------------------------------------------------------------
  # Instance helpers
  # ---------------------------------------------------------------------------

  # @return [Boolean] true when the asset carries AI provenance flags
  def ai_flagged?
    AI_STATUSES.include?(manifest_status)
  end

  # @return [Boolean]
  def verified?
    manifest_status == "verified"
  end

  # @return [Boolean]
  def missing_manifest?
    manifest_status == "missing"
  end

  # @return [Boolean]
  def needs_attention?
    %w[missing invalid error].include?(manifest_status)
  end
end
