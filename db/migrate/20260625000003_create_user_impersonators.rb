# Records which users are allowed to impersonate another user account.
#
# Row semantics: "impersonator_id CAN act as user_id".
# Both columns reference the users table; the constraint names distinguish them
# so PostgreSQL does not complain about ambiguous FK targets.
class CreateUserImpersonators < ActiveRecord::Migration[8.1]
  def change
    create_table :user_impersonators do |t|
      # The account being impersonated
      t.references :user,         null: false, foreign_key: true
      # The account allowed to impersonate
      t.references :impersonator, null: false,
                   foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :user_impersonators, [:user_id, :impersonator_id],
              unique: true,
              name: "index_user_impersonators_on_pair"
  end
end

