class BackfillParentIdFromClosureTable < ActiveRecord::Migration[8.0]
  def up
    # Set parent_id on every group whose direct parent is recorded in the
    # closure table (distance = 1) but whose parent_id column is still NULL.
    # This repairs rows that were linked via add_group_member before the
    # add_child method was updated to also write parent_id.
    execute <<~SQL
      UPDATE user_groups
      SET parent_id = ugc.ancestor_id
      FROM user_group_closures ugc
      WHERE user_groups.id = ugc.descendant_id
        AND ugc.distance = 1
        AND user_groups.parent_id IS NULL
    SQL
  end

  def down
    # Cannot reliably determine which parent_ids were set by this migration
    # versus set explicitly, so we leave them in place on rollback.
  end
end

