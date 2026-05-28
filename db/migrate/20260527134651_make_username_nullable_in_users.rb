class MakeUsernameNullableInUsers < ActiveRecord::Migration[7.0]
  def change
    # This allows existing and future records to have a NULL username
    change_column_null :users, :username, true

    # Optional: If you no longer want to enforce uniqueness on username,
    # you can remove the index. If you keep the index, ensure it allows NULLs.
    # remove_index :users, :username # Only run if you want to remove the index
  end
end