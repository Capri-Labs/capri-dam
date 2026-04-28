class AddAdminToUsers < ActiveRecord::Migration[8.0]
  def change
    # Only add the column if it's not already there
    unless column_exists?(:users, :admin)
      add_column :users, :admin, :boolean, default: false, null: false
    else
      # If it exists but we want to make sure the defaults are correct:
      change_column_default :users, :admin, from: nil, to: false
      change_column_null :users, :admin, false, false
    end
  end
end