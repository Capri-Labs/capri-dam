class ExpandUserDetails < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :first_name, :string
    add_column :users, :last_name, :string
    add_column :users, :role, :string, default: 'viewer' # e.g., admin, editor, viewer
    add_column :users, :active, :boolean, default: true
    add_column :users, :department, :string # Critical for Group-based workflows
    add_column :users, :avatar_url, :string
    add_column :users, :preferences, :jsonb, default: {} # For notification settings, theme, etc.

    # Add an index for active status and department for faster workflow routing
    add_index :users, :active
    add_index :users, :department
    add_index :users, :role
    add_index :users, :first_name
    add_index :users, :last_name

  end
end