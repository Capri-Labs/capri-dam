class AddOwnerToOauthApplications < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_applications, :owner_id, :integer
    add_column :oauth_applications, :owner_type, :string
  end
end
