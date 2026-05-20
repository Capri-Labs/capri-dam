class CreateUserGroupMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :user_group_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :user_group, null: false, foreign_key: true, index: true
      t.timestamps
    end
    # Ensure a user isn't duplicated inside the same group pool
    add_index :user_group_memberships, [:user_id, :user_group_id], unique: true
  end
end