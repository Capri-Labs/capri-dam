# frozen_string_literal: true

# Pushes a {StylePreset} to the AI Gateway so generation and style-transfer
# tasks can reference it by slug.
#
# The gateway is expected to respond to:
#   POST /api/style_presets   (upsert by slug)
#
# with { "ref": "<gateway-assigned-id>" }.
#
# On success the worker records +gateway_ref+ and +synced_at+ on the preset.
# On failure it logs and re-raises so Sidekiq can retry.
#
# Idempotency: if the preset no longer exists the worker no-ops.
#
# @see StylePreset
# @see Api::V1::StylePresetsController#sync
class StylePresetSyncWorker
  include Sidekiq::Worker

  sidekiq_options queue: "smartai", retry: 3

  def perform(style_preset_id)
    preset = StylePreset.find_by(id: style_preset_id)
    return unless preset

    dispatch_sync(preset)
  end

  private

  def dispatch_sync(preset)
    payload = {
      event:  "style.preset.sync",
      preset: {
        id:           preset.id,
        slug:         preset.slug,
        name:         preset.name,
        description:  preset.description,
        active:       preset.active,
        is_default:   preset.is_default,
        style_params: preset.style_params,
      },
    }.to_json

    Sidekiq.redis { |conn| conn.publish("ai_gateway_events", payload) }
    preset.update_columns(synced_at: Time.current)
  rescue StandardError => e
    Rails.logger.warn("[StylePresetSync##{preset.id}] sync failed: #{e.message}")
    raise
  end
end
