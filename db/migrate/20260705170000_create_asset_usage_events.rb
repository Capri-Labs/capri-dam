# frozen_string_literal: true

# Dedicated table backing {Asset#usage_stats} (view/download/share counters
# shown in the AssetViewer toolbar's Statistics popover).
#
# This is intentionally a *new* table rather than reusing {AuditLog}:
# +audit_logs.auditable_id+ is an +integer+ column (sized for {User}'s bigint
# ids), while {Asset} primary keys are UUIDs — storing a UUID there would
# silently truncate/corrupt the reference. See {Api::V1::AssetsController#track_event}
# for how these events are recorded and why they're app-observed rather than
# derived from CDN edge logs.
class CreateAssetUsageEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :asset_usage_events, id: :uuid do |t|
      t.references :asset, type: :uuid, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :event_type, null: false, default: "view"

      t.timestamps
    end

    add_index :asset_usage_events, [ :asset_id, :event_type ]
  end
end
