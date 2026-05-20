class CreateUserGroupsAndClosures < ActiveRecord::Migration[8.1]
  def change
    create_table :user_groups do |t|
      t.string :name, null: false
      t.string :description
      t.timestamps
    end
    add_index :user_groups, :name, unique: true

    # The Closure Table tracking infinite inheritance trees
    create_table :user_group_closures, id: false do |t|
      t.bigint :ancestor_id, null: false   # The Parent/Grandparent Group
      t.bigint :descendant_id, null: false # The Child/Sub-Group
      t.integer :distance, null: false     # Generation separation (0 = self, 1 = direct child, etc)
    end

    add_index :user_group_closures, [:ancestor_id, :descendant_id], unique: true, name: 'idx_group_closures_pk'
    add_index :user_group_closures, :descendant_id
  end
end