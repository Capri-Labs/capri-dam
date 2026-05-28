class AddGraphDataToWorkflows < ActiveRecord::Migration[7.0]
  def change
    add_column :workflows, :graph_data, :jsonb, default: {}
  end
end