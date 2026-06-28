# frozen_string_literal: true

# A named brand/style profile used during AI-assisted generation and
# style-transfer batch tasks.
#
# == Gateway sync
# Style presets are pushed to the AI Gateway via {StylePresetSyncWorker}.
# After a successful sync the row stores the gateway-assigned reference ID
# (+gateway_ref+) and a +synced_at+ timestamp so the UI can surface staleness.
#
# == Default preset
# At most one preset may be flagged +is_default+.  {promote_to_default!}
# handles the demotion of any previous default in a single transaction.
#
# == Broadcasting
# Every save emits a +style.preset.changed+ event on the
# +ai_gateway_events+ Redis channel so the gateway can invalidate caches.
#
# @see Api::V1::StylePresetsController
# @see StylePresetSyncWorker
class StylePreset < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  belongs_to :created_by, class_name: "User", optional: true

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :name, presence: true, length: { maximum: 120 }
  validates :slug,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: /\A[a-z0-9\-]+\z/, message: "only lowercase letters, numbers, and hyphens" },
            length: { maximum: 80 }

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  before_validation :derive_slug, on: :create
  after_commit :broadcast_preset_change, on: %i[create update destroy]

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  scope :active,      -> { where(active: true) }
  scope :defaults,    -> { where(is_default: true) }
  scope :synced,      -> { where.not(gateway_ref: nil) }
  scope :unsynced,    -> { where(gateway_ref: nil) }
  scope :recent,      -> { order(created_at: :desc) }

  # ---------------------------------------------------------------------------
  # Instance helpers
  # ---------------------------------------------------------------------------

  # @return [Boolean] true when the preset has been pushed to the gateway
  def synced?
    gateway_ref.present?
  end

  # @return [Boolean] true when the record is newer than the last gateway sync
  def stale?
    synced? && updated_at > synced_at
  end

  # Promotes this preset to the organisation default and demotes the current
  # default (if any) in a single transaction.
  def promote_to_default!
    transaction do
      StylePreset.where(is_default: true)
                 .where.not(id: id)
                 .update_all(is_default: false)
      update!(is_default: true)
    end
  end

  private

  def derive_slug
    return if slug.present?

    self.slug = name.to_s
                    .downcase
                    .gsub(/[^a-z0-9\s\-]/, "")
                    .gsub(/\s+/, "-")
                    .gsub(/-{2,}/, "-")
                    .strip
  end

  def broadcast_preset_change
    action = destroyed? ? "destroyed" : (previous_changes.key?("created_at") ? "created" : "updated")
    payload = {
      event: "style.preset.changed",
      action: action,
      preset: { id: id, slug: slug, name: name, active: active, is_default: is_default },
    }.to_json

    Sidekiq.redis { |conn| conn.publish("ai_gateway_events", payload) }
  rescue StandardError => e
    Rails.logger.warn("[StylePreset##{id}] preset broadcast skipped: #{e.message}")
  end
end
