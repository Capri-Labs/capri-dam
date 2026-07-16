class CreateCollectionPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :collection_policies do |t|
      t.references :collection, null: false, foreign_key: true
      t.references :user_group, null: false, foreign_key: true

      t.boolean :view_access,  default: false, null: false
      t.boolean :edit_access,  default: false, null: false
      t.boolean :admin_access, default: false, null: false
      t.boolean :explicit_deny, default: false, null: false

      t.timestamps
    end

    # One permission-tier configuration per group per collection.
    add_index :collection_policies, [ :collection_id, :user_group_id ], unique: true
  end
end
