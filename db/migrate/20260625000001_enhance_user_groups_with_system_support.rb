# Adds system-group protection columns to user_groups.
#
# * +is_system+  — immutable flag marking the 3 built-in groups
#   (administrators, super-administrators, everyone).  Rails-level guards
#   prevent deletion or slug changes on these rows.
# * +slug+       — machine-stable identifier used by application code
#   (never rely on the mutable +name+ column for logic).
# * +parent_id+  — optional self-referential parent for the closure-table
#   hierarchy.  NULL means the group lives at the root level.
class EnhanceUserGroupsWithSystemSupport < ActiveRecord::Migration[8.1]
  def change
    add_column :user_groups, :is_system, :boolean, default: false, null: false
    add_column :user_groups, :slug, :string
    add_column :user_groups, :parent_id, :bigint

    add_index :user_groups, :slug, unique: true
    add_index :user_groups, :parent_id

    add_foreign_key :user_groups, :user_groups, column: :parent_id
  end
end

