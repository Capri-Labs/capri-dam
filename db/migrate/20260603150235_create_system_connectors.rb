class CreateSystemConnectors < ActiveRecord::Migration[8.1]
  def change
    create_table :system_connectors do |t|
      t.string :name
      t.string :provider_type
      t.string :endpoint
      t.string :auth_token
      t.boolean :tdm_sanitation
      t.string :status
      t.datetime :last_sync
      t.integer :assets_imported

      t.timestamps
    end
  end
end
