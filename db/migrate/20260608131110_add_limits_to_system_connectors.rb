class AddLimitsToSystemConnectors < ActiveRecord::Migration[8.1]
  def change
    add_column :system_connectors, :concurrency_limit, :integer
    add_column :system_connectors, :rps_limit, :integer
  end
end
