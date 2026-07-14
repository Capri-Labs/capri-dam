# Backs "Publish Later" / "Unpublish Later" — a user picks a future date/time
# in the Explorer's Manage Publish menu instead of publishing/unpublishing
# immediately, and {PublishSchedulerWorker} (polling every 5 minutes, see
# config/schedule.rb) applies it once `scheduled_at` has passed.
#
# A dedicated table (rather than two nullable columns on `assets`) is used
# so that:
#   * an asset can have at most one *pending* schedule per action type,
#     enforced by the partial unique index below, without needing extra
#     nil-handling logic
#   * the audit trail of who scheduled what, and whether it ultimately
#     succeeded/failed/was cancelled, is preserved after execution
#   * cancelling a still-pending schedule doesn't require guessing which
#     column to null out
class CreateScheduledPublishActions < ActiveRecord::Migration[8.1]
  def change
    create_table :scheduled_publish_actions do |t|
      t.uuid :asset_id, null: false
      # "publish" or "unpublish" — validated at the model level (a DB check
      # constraint is avoided so the allowed set can evolve without a migration).
      t.string :action_type, null: false
      t.datetime :scheduled_at, null: false
      t.integer :status, null: false, default: 0 # pending / completed / cancelled / failed
      t.bigint :created_by_id, null: false
      t.datetime :executed_at
      t.text :error_message

      t.timestamps
    end

    add_index :scheduled_publish_actions, :asset_id
    add_index :scheduled_publish_actions, [ :status, :scheduled_at ], name: "index_scheduled_publish_actions_on_status_and_scheduled_at"
    # Only one pending schedule per (asset, action_type) at a time — a second
    # "Publish Later" request for the same asset should replace, not stack.
    add_index :scheduled_publish_actions, [ :asset_id, :action_type ],
              unique: true,
              where: "status = 0",
              name: "index_one_pending_schedule_per_asset_action"

    add_foreign_key :scheduled_publish_actions, :assets, column: :asset_id
    add_foreign_key :scheduled_publish_actions, :users, column: :created_by_id
  end
end
