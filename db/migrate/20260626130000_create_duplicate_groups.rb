# Migration: create the duplicate_groups and duplicate_group_assets tables
# that back the Duplicate Manager feature.
#
# duplicate_groups  — one row per unique SHA-256 checksum that has ≥2 matching
#                     assets in the repository.  Groups persist until resolved
#                     or dismissed by a user.
#
# duplicate_group_assets — join table that maps each group to the asset UUIDs
#                          that share the same checksum.
class CreateDuplicateGroups < ActiveRecord::Migration[8.1]
  def change
    # -------------------------------------------------------------------------
    # duplicate_groups
    # -------------------------------------------------------------------------
    create_table :duplicate_groups, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # The SHA-256 fingerprint shared by every asset in this group.
      t.string  :checksum,          null: false

      # Lifecycle: pending → resolved | dismissed
      t.string  :status,            null: false, default: "pending"

      # What the user chose when resolving: kept_all | deleted_duplicates
      t.string  :resolution_action

      # Total number of member assets (denormalised for fast list queries).
      t.integer :total_count,       null: false, default: 0

      # Audit fields for resolution.
      t.datetime :resolved_at
      t.bigint   :resolved_by_id

      t.timestamps
    end

    add_index :duplicate_groups, :checksum, unique: true
    add_index :duplicate_groups, :status
    add_index :duplicate_groups, :resolved_by_id

    # -------------------------------------------------------------------------
    # duplicate_group_assets
    # -------------------------------------------------------------------------
    create_table :duplicate_group_assets do |t|
      t.uuid    :duplicate_group_id, null: false
      t.uuid    :asset_id,           null: false

      # The earliest-created asset in the group is marked as the "original"
      # to give users a visual hint when choosing which copy to keep.
      t.boolean :is_original,        null: false, default: false

      t.timestamps
    end

    add_index :duplicate_group_assets,
              %i[duplicate_group_id asset_id],
              unique: true,
              name: "idx_dup_group_assets_unique"

    add_index :duplicate_group_assets, :asset_id
    add_index :duplicate_group_assets, :duplicate_group_id

    add_foreign_key :duplicate_groups,       :users,            column: :resolved_by_id
    add_foreign_key :duplicate_group_assets, :duplicate_groups, column: :duplicate_group_id,
                    primary_key: :id
    add_foreign_key :duplicate_group_assets, :assets, column: :asset_id,
                    primary_key: :id
  end
end
