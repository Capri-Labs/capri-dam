class AddWebhookSecretToSystemConnectors < ActiveRecord::Migration[8.1]
  def change
    add_column :system_connectors, :webhook_secret, :string
  end
end
